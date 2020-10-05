# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ #
# ~~~~~~~~~~~~~~~~~~~~~~~ RIP HS ~~~~~~~~~~~~~~~~~~~~~~~ #
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ #

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

        # Episode quality
        [Parameter(Mandatory=$false, 
                   Position=2)]
        [ValidateNotNull()]
        [ValidateNotNullOrEmpty()]
        [ValidateSet("1080p", "720p", "480p")]
        [string]
        $episode_quality = "1080p"
)

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ #
# ~~~~~~~~~~~~~~~~~~~~~ Don't Touch ~~~~~~~~~~~~~~~~~~~~ #
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ #

$ErrorActionPreference = "Stop"
[int] $torrent_check_internval_minutes = 1
[string] $horrible_subs_url = "https://horriblesubs.info/"

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Get all shows data

[string] $regex_folder_convention = "\s+?\-\s+?\d+$"
[string] $regex_episode_to_search = "\d+$"
[string] $horrible_subs_shows_url = "https://horriblesubs.info/shows/"
$shows_data = @()

$shows_folders = Get-ChildItem -LiteralPath $series_path -Directory -Depth 0 | `
                 ? {$_.BaseName -notmatch "\[IGNORE\]$"}

$horrible_subs_shows = Invoke-WebRequest -Uri $horrible_subs_shows_url -UseBasicParsing

Write-Host "[INFO] Getting shows folders that are actively being watched" -ForegroundColor Yellow -BackgroundColor DarkMagenta

foreach($show_folder in $shows_folders)
{
    [string] $show_folder_name = $show_folder | Select-Object -ExpandProperty Name

    if($show_folder_name -match $regex_folder_convention)
    {
        # Get show name
        [string] $show_name = $show_folder_name -replace $regex_folder_convention,''

        # Get episode to earch
        $show_folder_name -match $regex_episode_to_search | Out-Null
        [string] $folder_episode_to_search = $Matches[0]
        $Matches.Clear()

        # Get episodes in folder
        [string[]] $episodes_list = @()

        foreach($episode_name in (Get-ChildItem -Path $show_folder.FullName -File -Depth 0))
        {
            $episode_name.Name -match "\s+\-\s+\d+" | Out-Null
            $Matches[0] -match "\d+$" | Out-Null
            $episodes_list += [int]$Matches[0]
        }

        # Get show id in HorribleSubs
        [string] $show_href = $horrible_subs_shows.Links | `
                              ? {$_.title -eq $show_name} | `
                              Select-Object -ExpandProperty href

        if(!$show_href)
        {
            continue
        }

        (Invoke-WebRequest -Uri ($horrible_subs_url + $show_href) | Select-Object -ExpandProperty Content) -match "hs_showid.+" | Out-Null
        $Matches[0] -match "\d+" | Out-Null
        [string] $show_id = $Matches[0]

        # Set folder data
        $folder_data = [PSCustomObject] @{
                           'name' = $show_name
                           'episode_to_search' = $folder_episode_to_search
                           'episodes_in_folder' = $episodes_list
                           'hs_id' = $show_id
                           'folder_path' = $show_folder.FullName
                       }

        # Print data to user
        Write-Host "[  " -NoNewline -ForegroundColor Cyan
        Write-Host "SEARCH #$($folder_data.episode_to_search)" -NoNewline -ForegroundColor Yellow -BackgroundColor Black
    
        for([int] $k = 0;$k -lt (5 - $folder_data.episode_to_search.Length);$k++)
        {
            Write-Host " " -NoNewline -ForegroundColor Cyan
        }
    
        Write-Host "] $($folder_data.name)" -ForegroundColor Cyan


        # Add data to a collection for future use
        $shows_data += $folder_data
    }
}

Write-Host

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Download episodes 

[string] $horrible_subs_api_url = "https://horriblesubs.info/api.php?method=getshows&type=show"
[int] $number_of_torrents_downloading = 0

Write-Host "[INFO] Getting torrent magnet link for each show" -ForegroundColor Yellow -BackgroundColor DarkMagenta

foreach($show_data in $shows_data)
{
    [int] $counter = 0
    [int[]] $episodes_downloaded = @()

    while($show_episodes_page.Content -ne "DONE")
    {
        $show_episodes_page = Invoke-WebRequest -Uri "$horrible_subs_api_url&showid=$($show_data.hs_id)&nextid=$counter"
        $links = $show_episodes_page.Links

        foreach($link in $links)
        {
            if($link.title -and $link.title -eq "Magnet Link")
            {
                [string] $magnet = $link.href
            }

            # Check if correct link type to get link data
            if($link.innerHTML -and $link.innerHTML -eq 'XDCC')
            {
                # Check if is in the right quality
                if($link.href -and $link.href -match "\[HorribleSubs\].+" -and $link.href -match "\[$episode_quality\]")
                {
                    # Get episode number
                    $link.href -match "\w+\s+\[$episode_quality\]$" | Out-Null
                    $Matches[0] -match "^\d+" | Out-Null
                    [int] $episode_number = $Matches[0]
                    $Matches.Clear()

                    # Check if the episode is the one being searched for or after the one being searched fo
                    # Check if the episode is not already in the existing folder
                    # Check if the episode hasn't already been downloaded
                    if($episode_number -ge $show_data.episode_to_search -and `
                       $show_data.episodes_in_folder -notcontains $episode_number -and `
                       $episodes_downloaded -notcontains $episode_number)
                    {
                        start $magnet
                        $number_of_torrents_downloading++
                        $episodes_downloaded += $episode_number

                        Write-Host "[  " -NoNewline -ForegroundColor Cyan
                        Write-Host "DOWNLOADING" -NoNewline -ForegroundColor Yellow -BackgroundColor Black
                        Write-Host "  ] " -NoNewline -ForegroundColor Cyan
                        Write-Host "$($show_data.name) - $episode_number [$episode_quality].mkv" -ForegroundColor Cyan
                    }
                }
            }
        }

        $counter++
    }

    $show_episodes_page = $null
}

Write-Host

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Listening to torrent downloads

Write-Host "[INFO] Listening to torrents" -ForegroundColor Yellow -BackgroundColor DarkMagenta

if($number_of_torrents_downloading -eq 0)
{
    break
}

[int] $number_of_torrents_finished = 0
[int] $sleep_counter = 1

while($number_of_torrents_finished -lt $number_of_torrents_downloading)
{
    foreach($show_data in $shows_data)
    {
        # Get all files that match the [HorribleSubs] prefix, with the 'mkv' extension and match the show name
        $files_in_default_download_path = Get-ChildItem -Path $torrent_default_download_path -File -Depth 0 | `
                                          ? {$_.Extension -eq ".mkv" -and `
                                             $_.Name -match "^\[HorribleSubs\]" -and `
                                             $_.Name -match "$($show_data.name)"}


        foreach($file in $files_in_default_download_path)
        {
            try
            {
                    [string] $new_file_name = $file.Name -replace "(^\[HorribleSubs\] | \[$episode_quality\])",""
        
                    Move-Item -LiteralPath $file.FullName -Destination "$($show_data.folder_path)\$($new_file_name)"
        
                    Write-Host "[    " -NoNewline -ForegroundColor Cyan
                    Write-Host "MOVED" -NoNewline -ForegroundColor Yellow -BackgroundColor Black
                    Write-Host "      ] " -NoNewline -ForegroundColor Cyan
                    Write-Host " $($file.FullName)" -NoNewline -ForegroundColor Yellow -BackgroundColor Black
                    Write-Host " " -NoNewline
                    Write-Host "---->" -NoNewline -ForegroundColor Green
                    Write-Host " " -NoNewline
                    Write-Host "$($show_data.folder_path)\$new_file_name" -ForegroundColor Yellow -BackgroundColor Black
        
                    $number_of_torrents_finished++
            }
            catch{}
        }
    }

    if($number_of_torrents_finished -ne $number_of_torrents_downloading)
    {
        Start-Sleep -Seconds (60 * $torrent_check_internval_minutes)
        Write-Host "[  " -NoNewline -ForegroundColor Cyan
        Write-Host "$($sleep_counter * $torrent_check_internval_minutes) minutes" -NoNewline -ForegroundColor Yellow -BackgroundColor Black

        for([int]$k = 0;$k -lt (5 - ($sleep_counter * $torrent_check_internval_minutes).ToString().Length);$k++)
        {
            Write-Host " " -NoNewline
        }

        Write-Host "] " -NoNewline -ForegroundColor Cyan
        Write-Host "Still downloading" -ForegroundColor Cyan
        $sleep_counter += $torrent_check_internval_minutes
    }
}