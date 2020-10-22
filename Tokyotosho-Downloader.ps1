﻿# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ #
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
# Search episodes on shanaproject
# Get the magnet torrent site of each episode

Write-Host "[INFO] Getting torrent magnet link for each show" -ForegroundColor Yellow -BackgroundColor DarkMagenta

[string] $tokyotosho_url_start = "https://www.tokyotosho.info/search.php?terms"
[string] $tokyotosho_magnet_link_page_start = "https://www.tokyotosho.info/details.php"
$shows_episodes_found = @{}
[int] $num_torrents_downloading = 0
[string[]] $file_names = @()

foreach($show_to_search in $shows_to_search)
{
    foreach($uploader in $uploaders)
    {
        [int] $page_index = 1
        [bool] $reached_end = $false
        
        # Check if any torrents exist in the page
        while(!$reached_end)
        {
            [string] $full_url = "$tokyotosho_url_start=$show_to_search&username=$uploader&page=$page_index&type=1&searchName=true&size_min=&size_max="
            $page = Invoke-WebRequest -Uri $full_url

            if(!($page.ParsedHtml.IHTMLDocument3_getElementsByTagName("tr") | ? { $_.className -match "category_0"}))
            {
                $reached_end = $true
                continue
            }

            $page_episodes = $page.ParsedHtml.IHTMLDocument3_getElementsByTagName("tr") | ? { $_.className -match "category_0"}

            foreach($page_episode in $page_episodes)
            {
                if($page_episode.innerText -notmatch ($show_to_search -replace "\(","\(" -replace "\)","\)" -replace "\[","\[" -replace "\]","\]"))
                {
                    continue
                }

                # Fixing an error in the naming convetion with regards to a space in the extension name - '. mkv'  
                [string] $page_episode_name = $page_episode.children[1].innerText -replace "\.\s","."

                # Website to visit for magnet link
                [string] $page_episode_magnet_link_page_url = $tokyotosho_magnet_link_page_start + $page_episode.children[2].children[1].search

                # Skip episodes with a 'v2' added to their episode number eg. 148v2, 85v1 etc...
                if($page_episode_name -notmatch "\s+?\-\s+?\d+\s+")
                {
                    continue
                }

                $Matches.Clear()

                # Get episode number
                $page_episode_name -match "\s+?\-\s+?\d+\s+" | Out-Null
                $Matches[0] -match "\d+" | Out-Null
                [int] $page_episode_number = $Matches[0]

                $Matches.Clear()

                # Get episode quality
                $page_episode_name -match "\[\d+p\]" | Out-Null
                [string] $page_episode_quality = $Matches[0] -replace "[\[\]]",""

                $Matches.Clear()

                if($page_episode_number -ge $shows_episode_to_search[$show_to_search] -and `
                   $page_episode_number -notin $shows_episodes_in_folder[$show_to_search] -and `
                   $page_episode_quality -eq $episode_quality -and `
                   $shows_episodes_found.$show_to_search -notcontains $page_episode_number)
                {
                    if(!$shows_episodes_found.$show_to_search)
                    {
                        $shows_episodes_found.Add($show_to_search,$page_episode_number)
                    }
                    else
                    {
                        $shows_episodes_found.$show_to_search = $shows_episodes_found.$show_to_search,$page_episode_number
                    }

                    try
                    {
                        $page_episode_magnet_link_page = Invoke-WebRequest -Uri $page_episode_magnet_link_page_url

                        if($page_episode_magnet_link_page.Links | ? {$_.href -and $_.href -match "^magnet:"})
                        {
                            $href = ($page_episode_magnet_link_page.Links | ? {$_.href -and $_.href -match "^magnet:"}).href
                            $file_names += ($page_episode_magnet_link_page.Links | ? {$_.href -and $_.type -match "application/x-bittorrent"} | `
                                           Select-Object -ExpandProperty innerText) -replace "\s+\.","." -replace "\s+"," "

                            start $href
                        }

                        Write-Host "[  " -NoNewline -ForegroundColor Cyan
                        Write-Host "DOWNLOADING" -NoNewline -ForegroundColor Yellow -BackgroundColor Black
                        Write-Host "  ] " -NoNewline -ForegroundColor Cyan
                        Write-Host "[$uploader] $show_to_search - $page_episode_number [$episode_quality].mkv" -ForegroundColor Cyan

                        $num_torrents_downloading++
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
        }
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