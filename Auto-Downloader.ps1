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
        $torrent_check_internval = 1,

        # Episode quality
        [Parameter(Mandatory=$false, 
                   Position=4)]
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

[string] $regex_episode = "\s+?\-\s+?\d+"
[string] $horriblesubs_url = "https://horriblesubs.info/api.php?method=getshows&type=show&showid"

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

$shows_folders = $(Get-ChildItem -Path $series_path -Directory -Force -Attributes !H)

[string[]] $shows_to_search_for = @()

Write-Host "[INFO] Getting shows folders that are actively being watched" -ForegroundColor Yellow

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

        if($show_folder.FullName -match "(\[|\])")
        {
            $tmp_show_folder_full_name = $show_folder.FullName -replace '\[','``[' -replace '\]','``]'
        }
        else
        {
            $tmp_show_folder_full_name = $show_folder.FullName
        }

        [string[]] $episodes_in_folder = Get-ChildItem -Path $tmp_show_folder_full_name -Recurse |`
                                         Select-Object -ExpandProperty Name | % {
                                            if($_ -match $regex_episode)
                                            {
                                                $_ -match $regex_episode | Out-Null
                                                $Matches[0] -match "\d+" | Out-Null
                                                $Matches[0] -replace "^0",""
                                            }
                                         }

        [string] $show_name_without_episode_indication = $show_folder.Name -replace "$regex_episode$",""
        $shows_to_search_for += $show_name_without_episode_indication

        if($episodes_in_folder)
        {
            $shows_episodes_in_folder.Add($shows_to_search_for[-1],$episodes_in_folder)
        }
        else
        {
            $shows_episodes_in_folder.Add($shows_to_search_for[-1],-1)
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
    Write-Host "[INFO] Anime_Ids.txt file exists, checking last write time" -ForegroundColor Yellow
    $animes_ids_last_write_time = Get-ChildItem -Path $series_path\Animes_Ids.txt | Select-Object -ExpandProperty LastWriteTime

    if((New-TimeSpan -Start $animes_ids_last_write_time -End $(Get-Date) | Select-Object -ExpandProperty Days) -lt $update_anime_info_interval)
    {
        Write-Host "[INFO] Anime_Ids.txt was written less than $update_anime_info_interval day(s) ago, keeping info" -ForegroundColor Yellow
    }
    else
    {
        Write-Host "[INFO] Anime_Ids.txt was written more than $update_anime_info_interval day(s) ago, re-writing info" -ForegroundColor Yellow
        $get_horriblesubs_info = $true
        Remove-Item -Path "$series_path\Animes_Ids.txt" -Force | Out-Null
        New-Item -Path $series_path -Name "Animes_Ids.txt" -ItemType File -Force | Out-Null
    }
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

function Get-HorribleSubs-Info()
{
    if($get_horriblesubs_info)
    {
        [int] $counter = 0
        [int] $id = 0
    
        while($counter -lt 50)
        {
             $page = (Invoke-RestMethod -Method Get -UseBasicParsing -Uri "$horriblesubs_url=$id")

             if($page.GetType().Name -eq "XmlDocument")
             {
                $page = $page.InnerXml
             }

             $page = $page -split ">"
    
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
}

Get-HorribleSubs-Info

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

function Get-Show-Id()
{
    if($shows_info -cmatch $show_to_search_for)
    {
        $found_show_in_shows_info = $true
        [string]($shows_info -cmatch $show_to_search_for) -match "\d+" | Out-Null
        [string] $show_id_in_function = $Matches[0]
    }
    else
    {
        foreach($show_info in $shows_info)
        {
            if(($show_info -replace "\w+ \|\| ","") -eq $show_to_search_for)
            {
                $found_show_in_shows_info = $true
                break  
            }
        }

        $show_info -match "\d+" | Out-Null
        [string] $show_id_in_function = $Matches[0]
    }

    return $show_id_in_function,$found_show_in_shows_info
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Check if every show to search exists in the HorribleSubs info (id, name etc...)

Write-Host "`n[INFO] Checking if the shows are in the HorribleSubs info" -ForegroundColor Yellow

$shows_info = Get-Content -Path "$series_path\Animes_Ids.txt"

foreach($show_to_search_for in $shows_to_search_for)
{
    [boolean] $found_show_in_shows_info = $false
    [string] $show_id = ""
    $show_id,$found_show_in_shows_info = Get-Show-Id
    
    if($found_show_in_shows_info -eq $false)
    {
        Write-Host "[INFO] '$show_to_search_for' doesn't exist in the HorribleSubs info, re-creating Anime_Ids.txt file`n" -ForegroundColor Cyan

        Remove-Item -Path "$series_path\Animes_Ids.txt" -Force | Out-Null
        New-Item -Path $series_path -Name "Animes_Ids.txt" -ItemType File -Force | Out-Null
        $get_horriblesubs_info = $true
        Get-HorribleSubs-Info

        break
    }
    else
    {
        [int] $hazahot_num = 3 - $show_id.Length
        [string] $hazahot = ""

        for([int] $i = 0; $i -le $hazahot_num; $i++)
        {
             $hazahot += " "
        }

        Write-Host "[ $show_id $hazahot] $show_to_search_for" -ForegroundColor Cyan
    }
}

Write-Host

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Write-Host "[INFO] Getting torrent magnet link for each show" -ForegroundColor Yellow

[int] $torrents_downloading = 0
$shows_episodes_found = @{}

$shows_info = Get-Content -Path "$series_path\Animes_Ids.txt"

foreach($show_to_search_for in $shows_to_search_for)
{
    $page_links = @("place_holder")
    [string] $show_id = (Get-Show-Id)[0]
    [int] $show_page_interval = 0
    $show_page = ""

    if($show_to_search_for -match "(\[|\])")
    {
        $tmp_show_to_search_for = $show_to_search_for -replace "\[","\[" -replace "\]","\]"
    }
    else
    {
        $tmp_show_to_search_for = $show_to_search_for
    }

    while($page_links.Count -gt 0)
    {
        $page_links = Invoke-WebRequest -UseBasicParsing -Uri "$horriblesubs_url=$show_id&nextid=$show_page_interval" | Select-Object -ExpandProperty Links

        foreach($page_link in $page_links)
        {
            if($page_link.outerHTML -match "<strong>0?\d+</strong>")
            {
                $page_link.outerHTML -match "<strong>0?\d+</strong>" | Out-Null
                [int] $link_episode_number = $Matches[0] -replace "</?strong>",""
            }

            if($link_episode_number -ge $shows_episodes_to_search.$show_to_search_for -and $shows_episodes_in_folder.$show_to_search_for -notcontains $link_episode_number)
            {
                if($page_link.outerHTML -match "<a title=`"Magnet Link`"")
                {
                    [string] $magnet_link = $page_link.outerHTML -replace "^\<.+href=`"","" -replace "`"\>.+$"
                }
    
                if($page_link.href -and $page_link.href -match "$tmp_show_to_search_for - 0?$link_episode_number \[$episode_quality\]")
                {
                    $torrents_downloading++
                    start $magnet_link
                    $magnet_link = $null

                    if($show_to_search_for -match "(\[|\])")
                    {
                        $show_to_search_for = $show_to_search_for -replace "\\",""
                    }
                        
                    if(!$shows_episodes_found.Contains($show_to_search_for))
                    {
                        $shows_episodes_found.Add($show_to_search_for,$true)
                    }

                    Write-Host "[DOWNLOADING] $show_to_search_for #$link_episode_number $episode_quality" -ForegroundColor Cyan
                }
            }
        }

        $show_page_interval++
    }

    if(!$shows_episodes_found.Contains($show_to_search_for))
    {
        $shows_episodes_found.Add($show_to_search_for,$false)
    }
}

Write-Host

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

if($torrents_downloading -gt 0)
{
    Write-Host "[INFO] Listening to torrents" -ForegroundColor Yellow
    
    # Check every minute if all torrents finished downloading
    [int] $torrents_finished = 0
    [int] $sleep_counter = 1

    while($torrents_finished -ne $torrents_downloading)
    {
        $files_in_default_torrent_download_path = Get-ChildItem -Path $torrent_default_download_path -File -Force

        foreach($show_to_search_for in $shows_to_search_for)
        {
            $files = @()

            foreach($file in $files_in_default_torrent_download_path)
            {
                [string] $file_name = $file.Name -replace "^\[HorribleSubs\]\s","" -replace "\s-.+$",""

                if($file_name -eq $show_to_search_for)
                {
                    $files += $file
                }
            }

            if($files)
            {
                foreach($file in $files)
                {
                    try
                    {
                        Move-Item -LiteralPath $file.FullName -Destination "$series_path\$show_to_search_for - $($shows_episodes_to_search.$show_to_search_for)"
                        $torrents_finished++
                        Write-Host "[INFO] Moved $($file.FullName) to $series_path\$show_to_search_for - $($shows_episodes_to_search.$show_to_search_for)" -ForegroundColor Cyan
                    }
                    catch{}
                }
            }
        }

        if($torrents_finished -ne $torrents_downloading)
        {
            Start-Sleep -Seconds (60 * $torrent_check_internval)
            Write-Host "[$($sleep_counter * $torrent_check_internval) minutes] Still downloading" -ForegroundColor Yellow
            $sleep_counter++
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