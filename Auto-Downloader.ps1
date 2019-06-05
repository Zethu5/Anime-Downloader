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

$shows_folders = $(Get-ChildItem -Path $series_path -Directory -Force -Attributes !H)

[string[]] $shows_to_search_for = @()

Write-Host "[INFO] Getting shows folders that are actively being watched`n" -ForegroundColor Yellow

$shows_episodes_in_folder = @{}

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
                $shows_episodes_in_folder.Add($shows_to_search_for[-1],"")
            }
            
            if($show_episode_need_to_see -eq 0)
            {
                Write-Host "[SEARCH ALL]  $($shows_to_search_for[-1])" -ForegroundColor Cyan   
            }
            else
            {
                if([int]($show_episode_need_to_see) -lt 10) 
                {
                    $show_episode_need_to_see = "0$show_episode_need_to_see"
                }

                Write-Host "[SEARCH #$show_episode_need_to_see]  $($shows_to_search_for[-1])" -ForegroundColor Cyan   
            }
        }
    }
}
    
Write-Host ""

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
        Write-Host "[INFO] Anime_Ids.txt was written less than $update_anime_info_interval day(s) ago, keeping info`n" -ForegroundColor Yellow
    }
    else
    {
        Write-Host "[INFO] Anime_Ids.txt was written more than $update_anime_info_interval day(s) ago, re-writing info`n" -ForegroundColor Yellow
        $get_horriblesubs_info = $true
    }
}

if($get_horriblesubs_info)
{
    
}