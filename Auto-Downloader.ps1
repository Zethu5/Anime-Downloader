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