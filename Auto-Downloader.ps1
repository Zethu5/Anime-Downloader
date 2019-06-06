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

        # Update the anime info (in days)
        [Parameter(Mandatory=$false,
                   Position=2)]
        [ValidateNotNull()]
        [ValidateNotNullOrEmpty()]
        [int]
        $update_anime_info_interval = 7,

        # Torrent check interval (in minutes)
        [Parameter(Mandatory=$false, 
                   Position=3)]
        [ValidateNotNull()]
        [ValidateNotNullOrEmpty()]
        [int]
        $torrent_check_internval = 2,

        # Episode quality
        [Parameter(Mandatory=$false, 
                   Position=4)]
        [ValidateNotNull()]
        [ValidateNotNullOrEmpty()]
        [ValidateSet("1080p", "720p", "480p")]
        [string]
        $episode_quality = "1080p",

        
        # Episode quality
        [Parameter(Mandatory=$false, 
                   Position=5)]
        [ValidateNotNull()]
        [ValidateNotNullOrEmpty()]
        [switch]
        $download_all = $false
)

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ #
# ~~~~~~~~~~~~~~~~~~~~~ Don't Touch ~~~~~~~~~~~~~~~~~~~~ #
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ #

$ErrorActionPreference = "Stop"

[string] $regex_episode = "\s+?\-\s+?\d+"
[string] $horriblesubs_url = "https://horriblesubs.info/api.php?method=getshows&type=show&showid"

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

$shows_folders = $(Get-ChildItem -Path $series_path -Directory -Force -Attributes !H)

[string[]] $shows_to_search_for = @()

Write-Host "[INFO] Getting shows folders that are actively being watched`n" -ForegroundColor Yellow

$shows_episodes_in_folder = @{}
$shows_episodes_to_search = @{}

foreach($show_folder in $shows_folders)
{
    # If I started a show but didn't finish it - save it to check if new episodes are available
    if($show_folder.Name -notmatch "Finished" -and $show_folder.Name -match "$regex_episode$")
    {
        # Check if the episode I need to watch, already exists in the folder,
        # if so, go to the next show - no need to download an already existing episode
        $show_folder.Name -match $regex_episode | Out-Null
        $Matches[0] -match "\d+" | Out-Null
        [string] $show_episode_need_to_see = $Matches[0]

        [string[]] $episodes_in_folder = Get-ChildItem -Path $show_folder.FullName |`
                                         Select-Object -ExpandProperty Name | % {
                                            if($_ -match $regex_episode)
                                            {
                                                $_ -match $regex_episode | Out-Null
                                                $Matches[0] -match "\d+" | Out-Null
                                                $Matches[0] -replace "^0",""
                                            }
                                         }

        if($episodes_in_folder -notcontains $show_episode_need_to_see)
        {
            [string] $show_name_without_episode_indication = $show_folder.Name -replace "$regex_episode$",""
            $shows_to_search_for += $show_name_without_episode_indication

            if($episodes_in_folder)
            {
                $shows_episodes_in_folder.Add($shows_to_search_for[-1],$episodes_in_folder)
            }
            else
            {
                $shows_episodes_in_folder.Add($shows_to_search_for[-1],0)
            }
            
            if($show_episode_need_to_see -eq 0)
            {
                Write-Host "[SEARCH ALL]  $($shows_to_search_for[-1])" -ForegroundColor Cyan
                $shows_episodes_to_search.Add($shows_to_search_for[-1],0)   
            }
            else
            {
                $shows_episodes_to_search.Add($shows_to_search_for[-1], $show_episode_need_to_see)

                if([int]($show_episode_need_to_see) -lt 10) 
                {
                    $show_episode_need_to_see = "0$show_episode_need_to_see"
                }

                Write-Host "[SEARCH #$show_episode_need_to_see]  $($shows_to_search_for[-1])" -ForegroundColor Cyan   
            }
        }
    }
}
    
Write-Host

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Get all animes and their ids from horriblesubs
[boolean] $get_horriblesubs_info = $false

if(!(Test-Path "$series_path\Animes_Ids.txt"))
{
    Write-Host "[INFO] Anime_Ids.txt file does not exist, creating`n" -ForegroundColor Yellow
    New-Item -Path $series_path -Name "Animes_Ids.txt" -ItemType File -Force | Out-Null
    $get_horriblesubs_info = $true
}
else
{
    Write-Host "[INFO] Anime_Ids.txt file does exist, checking last write time" -ForegroundColor Yellow
    $animes_ids_last_write_time = Get-ChildItem -Path $series_path\Animes_Ids.txt | Select-Object -ExpandProperty LastWriteTime

    if((New-TimeSpan -Start $animes_ids_last_write_time -End $(Get-Date) | Select-Object -ExpandProperty Days) -lt $update_anime_info_interval)
    {
        Write-Host "[INFO] Anime_Ids.txt was written less than $update_anime_info_interval day(s) ago, keeping info" -ForegroundColor Yellow
    }
    else
    {
        Write-Host "[INFO] Anime_Ids.txt was written more than $update_anime_info_interval day(s) ago, re-writing info" -ForegroundColor Yellow
        $get_horriblesubs_info = $true
    }
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

if($get_horriblesubs_info)
{
    [int] $counter = 0
    [int] $id = 0

    while($counter -lt 50)
    {
         $page = (Invoke-RestMethod -Method Get -UseBasicParsing -Uri "$horriblesubs_url=$id") -split ">"

         if($page -eq "There are no individual episodes for this show")
         {
            $counter++
         }
         else
         {
            [string] $anime_name = $page[4] -replace "(^\s?|\s+\<.+)",""
            [string] $anime_info = "$id || $anime_name".ToString()
            Out-File -FilePath "$series_path\Animes_Ids.txt" -InputObject $anime_info -Append -Encoding utf8

            $counter = 0
         }

         $id++
    }

    Write-Host "[INFO] Anime_Ids.txt was re-written with new info" -ForegroundColor Yellow
}

#Intentionally here
Write-Host

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Write-Host "[INFO] Getting torrent magnet link for each show`n" -ForegroundColor Yellow

[int] $torrents_downloading = 0
$shows_episodes_found = @{}

$shows_info = Get-Content -Path "$series_path\Animes_Ids.txt"

foreach($show_to_search_for in $shows_to_search_for)
{
    [string]($shows_info -cmatch $show_to_search_for) -match "\d+" | Out-Null
    [string] $show_id = $Matches[0]
    [int] $show_page_interval = 0
    $show_page = ""

    while($show_page -ne "DONE")
    {
        $show_page = Invoke-WebRequest -UseBasicParsing -Uri "$horriblesubs_url=$show_id&nextid=$show_page_interval" | Select-Object -ExpandProperty Content
        $show_page_divs = $show_page -split '<div class="rls-links-container">'

        foreach($show_page_div in $show_page_divs)
        {
            if($show_page_div -match "id=`"0?\d+-$episode_quality`"")
            {
                $div -match "id=`"0?\d+-$episode_quality`"" | Out-Null
                [int] $div_episode_number = $Matches[0] -replace "(id=`"|-$episode_quality`")",""

                if($div_episode_number -ge $shows_episodes_to_search.$show_to_search_for -and $shows_episodes_in_folder.$show_to_search_for -notcontains $div_episode_number)
                {
                    $magnet_link = ($show_page_div `
                                    -split "class=`"rls-link link-$episode_quality`" id=`"0?\d+-$episode_quality`"><span class=`"rls-link-label`">$episode_quality`:</span><span class=`"dl-type hs-magnet-link`"><a title=`"Magnet Link`" href=`"" `
                                    -split "`">Magnet")[3]

                    if(!$shows_episodes_found.Contains($show_to_search_for))
                    {
                        $shows_episodes_found.Add($show_to_search_for,$true)
                    }
                }

                if($magnet_link)
                {
                    $torrents_downloading++
                    start $magnet_link
                    $magnet_link = $null
                    Write-Host "[DOWNLOADING] $show_to_search_for #$div_episode_number $episode_quality" -ForegroundColor Cyan
                }
            }
        }

        $show_page_interval++
    }

    if(!$shows_episodes_found.Contains($show_to_search_for))
    {
        $shows_episodes_found.Add($show_to_search_for,$false)
    }

    Write-Host
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

if($torrents_downloading -gt 0)
{
    Write-Host "[INFO] Checking if torrents finished downloading, interval: $torrent_check_internval minute(s)" -ForegroundColor Yellow
    
    # Check every minute if all torrents finished downloading
    [int] $torrents_finished = 0

    while($torrents_finished -ne $torrents_downloading)
    {
        $files_in_default_torrent_download_path = Get-ChildItem -Path $torrent_default_download_path -File -Force

        foreach($show_to_search_for in $shows_to_search_for)
        {
            if($files_in_default_torrent_download_path -match $show_to_search_for)
            {
                $files = $files_in_default_torrent_download_path -match $show_to_search_for

                foreach($file in $files)
                {
                    try
                    {
                        Move-Item -LiteralPath $file.FullName -Destination "$series_path\$show_to_search_for - $($shows_episodes_to_search.$show_to_search_for)"
                        $torrents_finished++
                        Write-Host "[INFO] Moved $($file.FullName) to $series_path\$show_to_search_for - $($shows_episodes_to_search.$show_to_search_for)" -ForegroundColor Yellow
                    }
                    catch{}
                }
            }
        }

        if($torrents_finished -ne $torrents_downloading)
        {
            Write-Host "[INFO] Still downloading, sleeping for $torrent_check_internval minute(s)" -ForegroundColor Yellow
            Start-Sleep -Seconds (60 * $torrent_check_internval)
        }
    }
}
else
{
    Write-Host "[INFO] Didn't find any episode to download, exiting" -ForegroundColor Yellow
}

Write-Host

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Rename all folders with '- 0' at the end to '- 1'
# to not search all episodes for this show again in the next run
foreach($show_to_search_for in $shows_to_search_for)
{
    if($shows_episodes_to_search.$show_to_search_for -eq 0)
    {
        if($shows_episodes_found.$show_to_search_for)
        {
            Write-Host "[INFO] All episodes were found for $show_to_search_for, renaming end to: '- 1'" -ForegroundColor Yellow
            Rename-Item -LiteralPath "$series_path\$show_to_search_for - $($shows_episodes_to_search.$show_to_search_for)" -NewName "$show_to_search_for - 1" -Force
        }

        Write-Host
    }
}