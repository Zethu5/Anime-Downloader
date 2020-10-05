# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ #
# ~~~~~~~~~~~~~~~~~~~~~~~ Config ~~~~~~~~~~~~~~~~~~~~~~~ #
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ #

Param
(
        # Anime series folder path
        [Parameter(Mandatory=$false, 
                   Position=0)]
        [ValidateNotNull()]
        [ValidateNotNullOrEmpty()]
        [string]
        $series_path = "E:\Series",

        # Torrent defalt download path
        [Parameter(Mandatory=$false, 
                   Position=1)]
        [ValidateNotNull()]
        [ValidateNotNullOrEmpty()]
        [string]
        $torrent_default_download_path = "E:\",

        # Torrent check interval (in minutes)
        [Parameter(Mandatory=$false, 
                   Position=2)]
        [ValidateNotNull()]
        [ValidateNotNullOrEmpty()]
        [int]
        $torrent_check_internval = 1,

        # Episode quality
        [Parameter(Mandatory=$false, 
                   Position=3)]
        [ValidateNotNull()]
        [ValidateNotNullOrEmpty()]
        [ValidateSet("1080p", "720p")]
        [string]
        $episode_quality = "1080p",

        # Uploaders
        [Parameter(Mandatory=$false, 
                   Position=4)]
        [ValidateNotNull()]
        [ValidateNotNullOrEmpty()]
        [string[]]
        $uploaders = @('Erai-raws','SSA')
)

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ #
# ~~~~~~~~~~~~~~~~~~~~~ Don't Touch ~~~~~~~~~~~~~~~~~~~~ #
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ #

$ErrorActionPreference = "Stop"

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Get all shows that are being watched

$shows_folders = Get-ChildItem -LiteralPath $series_path -Directory -Depth 0
[string[]] $folders_names = $shows_folders | Where-Object {$_.BaseName -notmatch "\s+?\-\s+?Ignore$"}`
                                           | Select-Object -ExpandProperty Name
[string[]] $shows_being_watched = @()
[string] $regex_episode_indicator = "\s+?\-\s+?\d+"

foreach($folder_name in $folders_names)
{
    if($folder_name -match $regex_episode_indicator)
    {
        $shows_being_watched += $folder_name
    }
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Get the episode that's needed to be searched for each show

$shows_episode_to_search = @{}
[string[]] $shows_to_search = @()

Write-Host "[INFO] Getting shows folders that are actively being watched" -ForegroundColor Yellow -BackgroundColor DarkMagenta

foreach($show_being_watched in $shows_being_watched)
{
    [string] $show_name = $show_being_watched -replace $regex_episode_indicator,""

    $show_being_watched -match "\d+$" | Out-Null
    [string] $episode_to_search = $Matches[0]

    $shows_episode_to_search.Add($show_name,$episode_to_search)
    $shows_to_search += $show_name

    Write-Host "[  " -NoNewline -ForegroundColor Cyan
    Write-Host "SEARCH #$episode_to_search" -NoNewline -ForegroundColor Yellow -BackgroundColor Black

    for([int] $k = 0;$k -lt (5 - $episode_to_search.Length);$k++)
    {
        Write-Host " " -NoNewline -ForegroundColor Cyan
    }

    Write-Host "] $show_name" -ForegroundColor Cyan
}

Write-Host

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Get episodes that exist in each show folder that is being watched

$shows_episodes_in_folder = @{}

foreach($show_being_watched in $shows_being_watched)
{
    [string] $show_name = $show_being_watched -replace $regex_episode_indicator,""

    $show_being_watched -match $regex_episode_indicator | Out-Null
    $Matches[0] -match "\d+" | Out-Null
    [string] $show_episode_need_to_see = $Matches[0]

    [string[]] $episodes_in_folder = Get-ChildItem -LiteralPath "$series_path\$show_being_watched" `
                                                    -Recurse |`
                                     Select-Object -ExpandProperty Name | % {
                                        if($_ -match $regex_episode_indicator)
                                        {
                                            $_ -match $regex_episode_indicator | Out-Null
                                            $Matches[0] -match "\d+" | Out-Null
                                            $Matches[0] -replace "^0",""
                                        }
                                     }

    $shows_episodes_in_folder.Add($show_name,$episodes_in_folder) | Out-Null
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

[string] $nyaa_url_start = "https://nyaa.net/search/"
[string] $nyaa_url_filters = "?c=3_&q="
[boolean] $reached_end = $false
[string[]] $file_names = @()
[int] $num_torrents_downloading = 0
$shows_episodes_found = @{}

Write-Host "[INFO] Getting torrent magnet link for each show" -ForegroundColor Yellow -BackgroundColor DarkMagenta

foreach($show_to_search in $shows_to_search)
{
    [string] $show_prefix_in_nyaa = $show_to_search -replace "\s+","+"
    [int] $nyaa_url_page = 1
    $page = ""
    
    while(!$reached_end)
    {
        for([int] $i = 0;$i -lt $uploaders.Length;$i++)
        {
            [string]$uploader_prefix = "[$($uploaders[$i])] "
            [string] $full_url = $nyaa_url_start + $nyaa_url_page + $nyaa_url_filters + $uploader_prefix + $show_prefix_in_nyaa + " " + $episode_quality
            $page = Invoke-WebRequest -UseBasicParsing -Uri $full_url
            $links = $page.Links

            [string] $show_and_episode_prefix = "\[$($uploaders[$i])\]?\s+$($show_to_search)?.+?\s+\-?\s+\d+.+\[$episode_quality\]" -replace "\'","\&\#39\;"

            for([int] $j = 0;$j -lt $links.Count; $j++)
            {
                # Check if the show name and episode quality match the user prefrences
                if($links[$j].outerHTML -and $links[$j].outerHTML -match $show_and_episode_prefix)
                {
                    $links[$j].outerHTML -match $show_and_episode_prefix | Out-Null

                    # Continue to next link if could'nt get the link episode number
                    $link_episode_number = ($Matches[0] -replace ".+\s+\-\s+","" -split "\s+")[0]

                    if(($Matches[0] -replace ".+\s+\-\s+","" -split "\s+")[0] -match "[^\d]+")
                    {
                        if($Matches[0] -eq "v")
                        {
                            $link_episode_number -match "\d+" | Out-Null
                            [string] $link_episode_number = [int]$Matches[0]
                        }
                        else
                        {
                            continue
                        }
                    }
                    else
                    {
                        [string] $link_episode_number = [int]($Matches[0] -replace ".+\s+\-\s+","" -split "\s+")[0]
                    }

                    # Check if the episode exists in the folder / is greater than the one searched for
                    # Check if the episode has already been downloaded (prevent downloading same episode from multiple publishers)
                    if([int]$link_episode_number -ge $shows_episode_to_search.$show_to_search -and `
                        $shows_episodes_in_folder.$show_to_search -notcontains $link_episode_number -and `
                        $shows_episodes_found.$show_to_search -notcontains $link_episode_number)
                    {
                        $links[$j+1].outerHTML -match "magnet.+/announce" | Out-Null
                        [string] $magnet_link = $Matches[0]

                        # disabled for testing purposes
                        start $magnet_link

                        Write-Host "[  " -NoNewline -ForegroundColor Cyan
                        Write-Host "DOWNLOADING" -NoNewline -ForegroundColor Yellow -BackgroundColor Black
                        Write-Host "  ] " -NoNewline -ForegroundColor Cyan
                        Write-Host "[$($uploaders[$i])] $show_to_search - $link_episode_number [$episode_quality].mkv" -ForegroundColor Cyan

                        $tmp = $links[$j].outerHTML -split "\n"
                        $tmp[1] -match "[^\s]+.+" | Out-Null
                        $file_names += $Matches[0] -replace "\&\#39\;","'"

                        if(!$shows_episodes_found.$show_to_search)
                        {
                            $shows_episodes_found.Add($show_to_search,$link_episode_number)
                        }
                        else
                        {
                            $shows_episodes_found.$show_to_search = $shows_episodes_found.$show_to_search,$link_episode_number
                        }

                        $num_torrents_downloading++
                    }
                }
            }
        }

        if($page.Images.alt -contains "no results")
        {
            $reached_end = $true
        }
        
        $nyaa_url_page++
    }

    $reached_end = $false
}

Write-Host

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

if($num_torrents_downloading -gt 0)
{
    Write-Host "[INFO] Listening to torrents" -ForegroundColor Yellow -BackgroundColor DarkMagenta

    [int] $num_torrents_finished = 0
    [int] $sleep_counter = 1

    while($num_torrents_finished -lt $num_torrents_downloading)
    {
        foreach($show_to_search in $shows_to_search)
        {
            $file_names_that_match = $file_names -match ("$show_to_search`?\s+\-?\s+" -replace "\(","\(" -replace "\)","\)")

            foreach($file in $file_names_that_match)
            {
                $Matches.Clear()
                [string] $file -match "$(("$show_to_search`?\s+\-?\s+" -replace "\(","\(" -replace "\)","\)"))\d+" | Out-Null
                $Matches[0] -match "\d+$" | Out-Null

                [string] $file_episode_number = $Matches[0]
                [string] $file_prefix = "$show_to_search - $file_episode_number.mkv"

                try
                {
                    Move-Item -LiteralPath "$torrent_default_download_path\$file" -Destination "$series_path\$show_to_search - $($shows_episode_to_search.$show_to_search)\$file_prefix"
                    $num_torrents_finished++
                    Write-Host "[    " -NoNewline -ForegroundColor Cyan
                    Write-Host "MOVED" -NoNewline -ForegroundColor Yellow -BackgroundColor Black
                    Write-Host "      ] " -NoNewline -ForegroundColor Cyan
                    Write-Host " $torrent_default_download_path$file" -NoNewline -ForegroundColor Yellow -BackgroundColor Black
                    Write-Host " " -NoNewline
                    Write-Host "---->" -NoNewline -ForegroundColor Green
                    Write-Host " " -NoNewline
                    Write-Host "$series_path\$show_to_search - $($shows_episode_to_search.$show_to_search)\$file_prefix" -ForegroundColor Yellow -BackgroundColor Black
                }
                catch{}
            }
        }

        if($num_torrents_finished -ne $num_torrents_downloading)
        {
            Start-Sleep -Seconds (60 * $torrent_check_internval)
            Write-Host "[  " -NoNewline -ForegroundColor Cyan
            Write-Host "$($sleep_counter * $torrent_check_internval) minutes" -NoNewline -ForegroundColor Yellow -BackgroundColor Black

            for([int]$k = 0;$k -lt (5 - ($sleep_counter * $torrent_check_internval).ToString().Length);$k++)
            {
                Write-Host " " -NoNewline
            }

            Write-Host "] " -NoNewline -ForegroundColor Cyan
            Write-Host "Still downloading" -ForegroundColor Cyan
            $sleep_counter++
        }
    }
}
else
{
    Write-Host "[INFO] Didn't find any episode to download, exiting" -ForegroundColor Yellow -BackgroundColor DarkMagenta
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

if($num_torrents_downloading -gt 0)
{
    Write-Host "[INFO] Renaming names of new folders" -ForegroundColor Yellow -BackgroundColor DarkMagenta

    foreach($folder_name in $folders_names)
    {
        if($folder_name -match "\s+?\-\s+?0$")
        {
            [string] $folder_name_without_zero_at_the_end = $folder_name -replace '\s+?\-\s+?0$',''

            if($shows_episodes_found.Keys -match $folder_name_without_zero_at_the_end)
            {
                try
                {
                    Rename-Item -Path "$series_path\$folder_name" -NewName "$folder_name_without_zero_at_the_end - 1"
                    Write-Host "[   " -NoNewline -ForegroundColor Cyan
                    Write-Host "RENAMING" -NoNewline -ForegroundColor Yellow -BackgroundColor Black
                    Write-Host "    ] " -NoNewline -ForegroundColor Cyan
                    Write-Host "$folder_name" -NoNewline -ForegroundColor Yellow -BackgroundColor Black
                    Write-Host " " -NoNewline
                    Write-Host "---->" -NoNewline -ForegroundColor Green
                    Write-Host " " -NoNewline
                    Write-Host "$folder_name_without_zero_at_the_end - 1" -ForegroundColor Yellow -BackgroundColor Black
                }
                catch
                {
                    Write-Host "[     ERROR     ] There was an error renaming the folder '$folder_name' to '$folder_name - 1'" -ForegroundColor Red
                }
            }
        }
    }
}