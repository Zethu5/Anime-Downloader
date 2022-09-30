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
        [ValidateSet("1080p", "720p", "480p")]
        [string]
        $episode_quality = "1080p",

        # Uploaders
        [Parameter(Mandatory=$false, 
                   Position=4)]
        [ValidateNotNull()]
        [ValidateNotNullOrEmpty()]
        [string[]]
        $uploaders = @('Erai-raws','SSA','SmallSizedAnimations', 'SubsPlease')
)

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ #
# ~~~~~~~~~~~~~~~~~~~~~ Don't Touch ~~~~~~~~~~~~~~~~~~~~ #
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ #

$ErrorActionPreference = "Stop"

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Check if Microsoft Office is intalled

if(!(Get-ItemProperty 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' | `
   ? {$_.Publisher -eq "Microsoft Corporation" -and ($_.DisplayName -match "Microsoft Office" -or $_.DisplayName -match "Microsoft 365")}))
{

    Write-Host "[     " -NoNewline -ForegroundColor Red
    Write-Host "ERROR" -NoNewline -ForegroundColor Red -BackgroundColor Black
    Write-Host "     ] " -NoNewline -ForegroundColor Red
    Write-Host "Didn't find an installation of Microsoft Office" -ForegroundColor Red

    pause
    break
}


# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Get all shows that are being watched

$shows_folders = @(Get-ChildItem -LiteralPath $series_path -Directory -Depth 0)

[string[]] $shows_being_watched = @()
[string] $regex_episode_indicator = "(\s+)?\-(\s+)?\d+$"

foreach($folder_name in $shows_folders)
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
    $Matches.Clear()

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
                                        if($_ -match "(\s+)?\-(\s+)?\d+.+\.\w+$")
                                        {
                                            $_ -match $regex_episode_indicator | Out-Null
                                            $Matches[0] -match "\d+" | Out-Null
                                            $Matches[0] -replace "^0",""
                                        }
                                     }

    $shows_episodes_in_folder.Add($show_name,$episodes_in_folder) | Out-Null
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Search episodes on tokyotosho
# Get the magnet torrent site of each episode

Write-Host "[INFO] Getting torrent magnet link for each show" -ForegroundColor Yellow -BackgroundColor DarkMagenta

[string] $tokyotosho_url_clean = "https://www.tokyotosho.info"
[string] $tokyotosho_url_start = "https://www.tokyotosho.info/search.php?terms"
[string] $tokyotosho_magnet_link_page_start = "https://www.tokyotosho.info/details.php"
$shows_episodes_found = @{}
[int] $num_torrents_downloading = 0
$file_names_and_where_to_put_them = @{}
[string] $tokyotosho_warning_search_limit = "Exceeded search limit per hour \(200\)"


# check if the site is up
try
{
    Invoke-WebRequest -Uri $tokyotosho_url_clean | Out-Null
}
catch
{
    Write-Host "[     " -NoNewline -ForegroundColor Cyan
    Write-Host "ERROR" -NoNewline -ForegroundColor Red -BackgroundColor Black
    Write-Host "     ] " -NoNewline -ForegroundColor Cyan
    Write-Host "Couldn't reach $tokyotosho_url_clean, site down?" -ForegroundColor Red -BackgroundColor Black
    break
}


:outer foreach($show_to_search in $shows_to_search)
{
    [boolean] $got_show_episode_searched_for = $false
    [bool] $found_some_episode_for_show = $false

    foreach($uploader in $uploaders)
    {
        [int] $page_index = 1
        [bool] $reached_end = $false
        
        # Check if any torrents exist in the page
        while(!$reached_end)
        {
            [string] $full_url = "$tokyotosho_url_start=$show_to_search $episode_quality&username=$uploader&page=$page_index&type=1&searchName=true"
            $page = Invoke-WebRequest -Uri $full_url

            if($page.RawContent -match $tokyotosho_warning_search_limit)
            {
                Write-Host "[     " -NoNewline -ForegroundColor Cyan
                Write-Host "ERROR" -NoNewline -ForegroundColor Red -BackgroundColor Black
                Write-Host "     ] " -NoNewline -ForegroundColor Cyan
                Write-Host "Exceeded torrent search limit per hour (200)" -ForegroundColor Red -BackgroundColor Black

                break outer
            }

            if(!($page.ParsedHtml.IHTMLDocument3_getElementsByTagName("tr") | ? { $_.className -match "category_0"}))
            {
                $reached_end = $true
                continue
            }

            $page_episodes = $page.ParsedHtml.IHTMLDocument3_getElementsByTagName("tr") | ? { $_.className -match "category_0" -and 
                                                                                              $_.children[2] -and 
                                                                                              $_.children[2].children[1] -and
                                                                                              $_.children[2].children[1].search -match "\?id=\d+"}

            foreach($page_episode in $page_episodes)
            {
                [string] $regex_replace_space_class = ""
                [string] $regex_dot_string = ""

                # '-gt 1' because the files will always end with a '.mkv' file extension
                if(($page_episode.children[1].children[1].children | ? {$_.className -eq "s"}).Count -gt 1)
                {
                      $regex_space_class = "\.\s+"
                      $regex_dot_string = "."
                }

                if($page_episode.innerText -replace $regex_space_class,$regex_dot_string -notmatch `
                  ("$($show_to_search -replace "\(","\(" -replace "\)","\)" -replace "\[","\[" -replace "\]","\]")\s+?\-\s+?"))
                {
                    continue
                }

                # Fixing an error in the naming convetion with regards to a space in the extension name - '. mkv'  
                [string] $page_episode_name = $page_episode.children[1].innerText -replace "\.\s","."

                # Website to visit for magnet link
                [string] $page_episode_magnet_link_page_url = $tokyotosho_magnet_link_page_start + $page_episode.children[2].children[1].search

                if($page_episode_name -notmatch "\s+?\-\s+?\d+(v\d+)?\s+")
                {
                    continue
                }

                $Matches.Clear()

                # Get episode number
                $page_episode_name -match "\s+?\-\s+?\d+(v\d+)?\s+" | Out-Null
                $Matches[0] -match "\d+" | Out-Null
                [int] $page_episode_number = $Matches[0]

                $Matches.Clear()

                # if the first episode number in this page is lower than the one we are searching for,
                # there is no reason to continue searching other pages, we can safely break
                if($page_episode_number -lt $shows_episode_to_search[$show_to_search])
                {
                    $got_show_episode_searched_for = $true
                }

                # Get episode quality
                $page_episode_name -match "(\[\d+p\]|\(\d+p\))" | Out-Null
                [string] $page_episode_quality = $Matches[0] -replace "[\[\]\(\)]",""

                $Matches.Clear()

                if($page_episode_number -ge $shows_episode_to_search[$show_to_search] -and `
                   $page_episode_number -notin $shows_episodes_in_folder[$show_to_search] -and `
                   $page_episode_quality -eq $episode_quality -and `
                   $shows_episodes_found.$show_to_search -notcontains $page_episode_number)
                {
                    if(!$shows_episodes_found.$show_to_search)
                    {
                        $shows_episodes_found.Add($show_to_search,@($page_episode_number))
                    }
                    else
                    {
                        $shows_episodes_found.$show_to_search += $page_episode_number
                    }

                    try
                    {
                        $page_episode_magnet_link_page = Invoke-WebRequest -Uri $page_episode_magnet_link_page_url

                        if($page_episode_magnet_link_page.Links | ? {$_.href -and $_.href -match "^magnet:"})
                        {
                            $href = ($page_episode_magnet_link_page.Links | ? {$_.href -and $_.href -match "^magnet:"}).href
                            $file_name = ($page_episode_magnet_link_page.Links | ? {$_.href -and $_.type -match "application/x-bittorrent"} | `
                                         Select-Object -ExpandProperty innerText) -replace "\s+\.","." -replace "\s+"," "

                            $file_names_and_where_to_put_them.Add($file_name,($shows_folders -match ($show_to_search -replace "\(","\(" -replace "\)","\)" -replace "\[","\[" -replace "\]","\]")).Name)
                            start $href
                        }

                        Write-Host "[  " -NoNewline -ForegroundColor Cyan
                        Write-Host "DOWNLOADING" -NoNewline -ForegroundColor Yellow -BackgroundColor Black
                        Write-Host "  ] " -NoNewline -ForegroundColor Cyan
                        Write-Host "[$uploader] $show_to_search - $page_episode_number [$episode_quality].mkv" -ForegroundColor Cyan

                        $found_some_episode_for_show = $true
                        $num_torrents_downloading++

                        # if the page episode number is equal to the one we are searching for in this specific show, 
                        # there's no need to continue to query later pages because they will only display older episodes, which is unnecessary
                        if($page_episode_number -eq $shows_episode_to_search[$show_to_search])
                        {
                            $got_show_episode_searched_for = $true
                        }
                    }
                    catch
                    {
                        Write-Host "[     " -NoNewline -ForegroundColor Cyan
                        Write-Host "ERROR" -NoNewline -ForegroundColor Red -BackgroundColor Black
                        Write-Host "     ] " -NoNewline -ForegroundColor Cyan
                        Write-Host "Couldn't download $show_to_search - $page_episode_number [$episode_quality]: $($Error[0].Exception.Message)" -ForegroundColor Red -BackgroundColor Black
                    }
                }
            }

            $page_index++
            $Matches.Clear()

            if($got_show_episode_searched_for)
            {
                break
            }
        }
    }

    if(!$found_some_episode_for_show)
    {
        Write-Host "[ " -NoNewline -ForegroundColor Cyan
        Write-Host "NOTHING FOUND" -NoNewline -ForegroundColor Yellow -BackgroundColor Black
        Write-Host " ] " -NoNewline -ForegroundColor Cyan
        Write-Host "$show_to_search" -ForegroundColor DarkCyan
    }
}

Write-Host
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Listen to torrents and move episodes to their destinations

if($num_torrents_downloading -gt 0)
{
    Write-Host "[INFO] Listening to torrents" -ForegroundColor Yellow -BackgroundColor DarkMagenta

    [int] $num_torrents_finished = 0
    [int] $sleep_counter = 1

    while($num_torrents_finished -lt $num_torrents_downloading)
    {
        foreach($record in $file_names_and_where_to_put_them.GetEnumerator())
        {
            $Matches.Clear()
            $record.Key -match "$(("\s+?\-\s+?" -replace "\(","\(" -replace "\)","\)"))\d+" | Out-Null
            $Matches[0] -match "\d+$" | Out-Null
            
            [string] $file_episode_number = $Matches[0]
            [string] $file_prefix = "$($record.Value -replace "\s+?\-\s+?\d+$") - $file_episode_number.mkv"
            
            try
            {
                Move-Item -LiteralPath "$torrent_default_download_path\$($record.Key)" -Destination "$series_path\$($record.Value)\$file_prefix"
                $num_torrents_finished++
                Write-Host "[    " -NoNewline -ForegroundColor Cyan
                Write-Host "MOVED" -NoNewline -ForegroundColor Yellow -BackgroundColor Black
                Write-Host "      ] " -NoNewline -ForegroundColor Cyan
                Write-Host " $torrent_default_download_path$($record.Key)" -NoNewline -ForegroundColor Yellow -BackgroundColor Black
                Write-Host " " -NoNewline
                Write-Host "---->" -NoNewline -ForegroundColor Green
                Write-Host " " -NoNewline
                Write-Host "$series_path\$($record.Value) - $($shows_episode_to_search.$show_to_search)\$file_prefix" -ForegroundColor Yellow -BackgroundColor Black
            }
            catch{}
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
