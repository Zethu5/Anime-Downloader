# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ #
# ~~~~~~~~~~~~~~~~~~~~~~~ Config ~~~~~~~~~~~~~~~~~~~~~~~ #
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ #
[string] $series_path = "E:\Series"
[string] $torrent_default_download_path = "E:\"
[int] $update_anime_info_interval = 7 # In days
[int] $torrent_check_internval = 1 # In minutes


# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ #
# ~~~~~~~~~~~~~~~~~~~~~ Don't Touch ~~~~~~~~~~~~~~~~~~~~ #
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ #

$ErrorActionPreference = "Stop"

[string] $regex_episode = "\s+?\-\s+?\d+"
[string] $horriblesubs_url = "https://horriblesubs.info/api.php?method=getshows&type=show&showid"

$shows_folders = $(Get-ChildItem -Path $series_path -Directory -Force)

[string[]] $shows_names = @()

Write-Host "[INFO] Getting shows folders that are actively being watched`n" -ForegroundColor Yellow

$shows_episodes_in_folder = @{}

foreach($show_folder in $shows_folders)
{
    # If I started a show but didn't finish it - save it to check if new episodes are available
    if($show_folder.Name -notmatch "Finished" -and $show_folder.Name -match "$regex_episode$")
    {
        # Check if the episode I need to watch, already exists in the folder,
        # if so, go to the next show - no need to download an already existing episode
        $show_folder.Name -match "\s+\-\s+\d+" | Out-Null
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
            $shows_names += $($show_folder.Name -replace "$regex_episode$","")

            if($episodes_in_folder)
            {
                $shows_episodes_in_folder.Add($shows_names[-1],$episodes_in_folder)
            }
            else
            {
                $shows_episodes_in_folder.Add($shows_names[-1],"")
            }
            
            
            Write-Host "[ACTION] Looking for $($shows_names[-1]) episode $show_episode_need_to_see" -ForegroundColor Cyan   
        }
    }
}

Write-Host ""

# Get all animes and their ids from horriblesubs
[boolean] $get_horriblesubs_info = $false

if(!(Test-Path "$series_path\Animes_Ids.txt"))
{
    Write-Host "[INFO] Anime_Ids.txt file does not exist, creating`n" -ForegroundColor Yellow
    New-Item -Path $series_path -Name "Animes_Ids.txt" -ItemType File -Value "$(Get-Date)`n" -Force | Out-Null
    $get_horriblesubs_info = $true
}
else
{
    Write-Host "[INFO] Anime_Ids.txt file does exist, checking write time`n" -ForegroundColor Yellow
    $animes_info = Get-Content -Path "$series_path\Animes_Ids.txt"

    try
    {    
        [DateTime]::Parse($animes_info[0]) | Out-Null

        if((New-TimeSpan -End (Get-Date) -Start $animes_info[0] | Select-Object -ExpandProperty Hours) -ge $update_anime_info_interval -or $animes_info -notmatch "||")
        {
            Write-Host "[ACTION] Anime_Ids.txt was written more than 1 day ago, re-writing info" -ForegroundColor Cyan
            $get_horriblesubs_info = $true
            New-Item -Path $series_path -Name "Animes_Ids.txt" -ItemType File -Value "$(Get-Date)`n" -Force | Out-Null
        }
        else
        {
            Write-Host "[INFO] Anime_Ids.txt was written less than 1 day ago, keeping info`n" -ForegroundColor Yellow
        }
    }
    catch{}
}

if($get_horriblesubs_info)
{
    [int] $counter = 0
    [int] $id = 0
    [boolean] $page_exists = $false
    $animes_info = @()

    while($counter -lt 50)
    {
        $page = (Invoke-RestMethod -Method Get -UseBasicParsing -Uri "$horriblesubs_url=$id") -split ">"

        if($page -eq "There are no individual episodes for this show")
        {
            $counter++
        }
        elseif($page[4] -match "\s+\<.+")
        {
            [string] $anime_name = $page[4] -replace "(^\s?|\s+\<.+)",""
            [string] $anime_info = "$id || $anime_name".ToString()
            Out-File -FilePath "$series_path\Animes_Ids.txt" -InputObject $anime_info -Append -Encoding utf8
            $page_exists = $true
        }

        if($counter -gt 0 -and $page_exists)
        {
            $counter = 0
        }

        $page_exists = $false
        $id++
    }

    Write-Host "[INFO] Anime_Ids.txt was re-written with new info" -ForegroundColor Yellow
}

$shows_info = Get-Content -Path "$series_path\Animes_Ids.txt"

if(!(Test-Path -Path "$series_path\Shows_Currently_Downloading.txt"))
{
    Write-Host "[ACTION] Shows_Currently_Downloading.txt does not exist, creating`n" -ForegroundColor Cyan
    New-Item -Path $series_path -Name "Shows_Currently_Downloading.txt" -ItemType File -Force | Out-Null
}
else
{
    Write-Host "[INFO] Shows_Currently_Downloading.txt does exist" -ForegroundColor Yellow
}

Write-Host "[INFO] Getting torrent magnet link for each show" -ForegroundColor Yellow

[boolean] $downloading_something = $false
[int] $number_of_torrents_downloading = 0

# Get torrent magnet link from each show page
foreach($show_name in $shows_names)
{
    if(!((Get-Content -Path "$series_path\Shows_Currently_Downloading.txt") -match $show_name))
    {
        [string] $episode_to_search = (($shows_folders -match $show_name).Name -split "\s+\-\s+")[1]
        $show_id = $shows_info -match $show_name -replace "\s\|\|\s.+",""
        $show_page = Invoke-WebRequest -UseBasicParsing -Uri "$horriblesubs_url=$show_id" | Select-Object -ExpandProperty Content
        $show_episodes_html = $show_page -split '<div class="rls-links-container">'

        foreach($div in $show_episodes_html)
        {
            if($div -match "id=`"0?\d+-1080p`"")
            {
                $div -match "id=`"0?\d+-1080p`"" | Out-Null
                [int] $div_episode_number = $Matches[0] -replace "(id=`"|-1080p`")",""

                if($div_episode_number -ge $episode_to_search -and $shows_episodes_in_folder.$show_name -notcontains $div_episode_number)
                {
                    $magnet_link = ($div -split "class=`"rls-link link-1080p`" id=`"0?\d+-1080p`"><span class=`"rls-link-label`">1080p:</span><span class=`"dl-type hs-magnet-link`"><a title=`"Magnet Link`" href=`"" -split "`">Magnet")[3]

                    if($magnet_link)
                    {
                        start $magnet_link
                        $downloading_something = $true
                        $number_of_torrents_downloading++

                        if(!((Get-Content -Path "$series_path\Shows_Currently_Downloading.txt") -cmatch "$show_name"))
                        {
                            Out-File -FilePath "$series_path\Shows_Currently_Downloading.txt" -InputObject $show_name -Append -Encoding utf8
                        }

                        Write-Host "[ACTION] Started downloading torrent for: $show_name episode $div_episode_number" -ForegroundColor Cyan
                    }
                }
            }
        }
    }
}

if($downloading_something)
{
    Write-Host "[INFO] Checking if torrents finished downloading, interval: $torrent_check_internval minute(s)" -ForegroundColor Yellow

    # Check every minute if all torrents finished downloading
    [int] $torrents_finished = 0

    while($torrents_finished -ne $number_of_torrents_downloading)
    {
        $files_in_default_torrent_download_path = Get-ChildItem -Path $torrent_default_download_path -File -Force

        foreach($show_name in $shows_names)
        {
            if($files_in_default_torrent_download_path -match $show_name)
            {
                $files = $files_in_default_torrent_download_path -match $show_name
                
                foreach($file in $files)
                {
                    try
                    {
                        Move-Item -LiteralPath $file.FullName -Destination "$series_path\$(($shows_folders).Name -match $show_name)"
                        $torrents_finished++
                        Write-Host "[INFO] Moved $($file.FullName) to $series_path\$(($shows_folders).Name -match $show_name)" -ForegroundColor Yellow
                    }
                    catch{}
                }
            }
        }

        if($torrents_finished -ne $number_of_torrents_downloading)
        {
            Write-Host "[INFO] Some torrents are still downloading, sleeping for $torrent_check_internval minute(s)" -ForegroundColor Yellow
            Start-Sleep -Seconds (60 * $torrent_check_internval)
        }
    }

    Write-Host "[INFO] Episodes were moved to their folders" -ForegroundColor Yellow
    Write-Host "[INFO] Removing Shows_Currently_Downloading.txt" -ForegroundColor Yellow
}
else
{
    Write-Host "[INFO] No new episodes are available for download, exiting" -ForegroundColor Yellow
}

Remove-Item -LiteralPath "$series_path\Shows_Currently_Downloading.txt" -Force