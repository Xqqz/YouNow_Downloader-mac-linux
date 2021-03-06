#!/bin/bash
#| 1.0   @nikisdro             [ 2015-07-25 ] |"
#|       * Windows script for YN downloading  |"
#|                                            |"
#| 1.1   truethug              [ 2016-02-05 ] |"
#|       * Extend script to linux/ mac        |"
#|                                            |"
#| 1.2   IcedPenguin           [ 2016-05-28 ] |"
#|       * Fix for new YN streaming format    |"
#|                                            |"
#| 1.3   IcedPenguin           [ 2016-06-?? ] |"
#|       * Updated the menuing system         |"
#|       * Added moment support               |"
#|                                            |"
#| 1.4  truethug               [ 2016-06-07 ] |"
#|      * Fixed Linux supprt                  |"
#| 1.5  throwaway404           [ 2016-08-31 ] |"
#|      * Fixed Api link                      |"
#+--------------------------------------------+"

verbose=false

source ./you_now_broadcasts.sh
source ./you_now_moments.sh

echo "+--------------------------------------------+"
echo "|        YouNow video downloader             |"
echo "+--------------------------------------------+"
echo "|       This script helps you download       |"
echo "|   YouNow.com broadcasts and live streams   |"
echo "+--------------------------------------------+"

function mainProgramLoop() {
    local status="running"
    while [[ "${status}" == "running" ]]; do
        echo ""
        echo "Enter username (leave blank to quit):" 
        read entered_name

        web=`echo $entered_name | grep 'younow.com'`
        if [ -z ${entered_name} ]
        then
            status="exit"

        elif [ "${web}" != "" ]; then
            user=`echo ${entered_name} | cut -d'/' -f4`
            userDownloadMenu ${user}
        else
            userDownloadMenu "${entered_name}"
        fi
    done
}

# Handles the user interaction for downloading videos for a YouNow user. This
# includes capturing live broadcasts, downloading past broadcasts, or downloading
# moments.
#
# @param: user_name
function userDownloadMenu()
{
    local user_name=$1

    while : ; do
        echo " "
        wget --no-check-certificate -q "https://api.younow.com/php/api/broadcast/info/user=${user_name}" -O "./_temp/${user_name}.json"
        local user_id=`xidel -q ./_temp/${user_name}.json -e '$json("userId")'`
        local error=`xidel -q ./_temp/${user_name}.json -e '$json("errorCode")'`
        local errorMsg=`xidel -q ./_temp/${user_name}.json -e '$json("errorMsg")'`
        #echo Error code: $error

        if [ "${error}" == "101" -o ! -s ./_temp/${user_name}.json  -o "${user_id}" == "" ]
        then
            echo "There was a problem with the provided user name."
            echo "    Error: $errorMsg"
            echo " "
            return

        elif [ "${error}" == "206" ]; then
            echo "What would you like to do: download past (B)roadcasts or download a (M)oment? (B / M)"

        else
            echo "[LIVE] ${user_name} is broadcasting now!"
            echo "What would you like to do: Capture (L)ive Broadcast, download past (B)roadcasts, or download a (M)oment? (L / B / M)"
        fi

        read user_action

        
        if [ "${user_action}" == "L" ] || [ "${user_action}" == "l" ]; then
            echo "LIVE mode."
            downloadLiveBroadcast "${user_name}"

        elif  [ "${user_action}" == "B" ] || [ "${user_action}" == "b" ]; then
            echo "Broadcast mode"
            downloadPreviousBroadcastsMenu $user_name $user_id

        elif  [ "${user_action}" == "M" ] || [ "${user_action}" == "m" ]; then
            echo "Moment mode"
            downloadMomentsMenu $user_name $user_id

        else
            return # user did not enter a command, return to previous menu.
        fi
        rm ./_temp/${user_name}.json
    done
}

# Performing the actual download of a live broadcasts. The download operation takes place
# in a child process (new shell window).
#
# @param: user_name
function downloadLiveBroadcast()
{
    local user_name=${1}

    local broadcast_id=`xidel -q ./_temp/${user_name}.json -e '$json("broadcastId")'`
    local temp=`xidel -q -e 'join(($json).media/(host,app,stream))' ./_temp/${user_name}.json`
    local host=`echo $temp | cut -d' ' -f1`
    local app=`echo $temp | cut -d' ' -f2`
    local stream=`echo $temp | cut -d' ' -f3`
    local ddate=`date +%h_%d,%G_%T`
    local filename=$(findNextAvailableFileName ${user_name} "flv" ${ddate})

    if [ ! -d "./videos/${user_name}" ]
    then
        mkdir "./videos/${user_name}"
    fi

    if [ "$mac" == "" ]
    then
        xterm -e "$rtmp -v -o ./videos/${user_name}/${filename} -r rtmp://$host$app/$stream;exit" &
    else
        echo "cd `pwd` ; rtmpdump -v -o ./videos/${user_name}/${filename} -r rtmp://$host$app/$stream" > "./_temp/${filename}.command"
        chmod +x "./_temp/${filename}.command"
        open "./_temp/${filename}.command"
#        rm ./_temp/${filename}.command
    fi
    echo " OK! Started recording in a separate window."
}

# Function to find a unique file name to record the video to. This prevents overwriting
# a previously recorded video. In the event of name colisions, the file is extended with
# the letter 'a'.
# 
# @param: user name
# @param: video type {live, broadcast, moment}
# @param: video id
# @param: extension
function findNextAvailableFileName() 
{
    local timestamp=$(date +%s)
    local user_name=$1
    local extension=$2
    local ddate=$3

    local base_video_name=${user_name}_${ddate}_T${timestamp}
    
    base_video_name="${base_video_name}.${extension}"
    echo ${base_video_name}
}

function checkDependencies()
{
    dependencies=( "rtmpdump" "xidel" "wget" "ffmpeg")

    for i in "${dependencies[@]}"
    do
        :
        if ! hash ${i} 2>/dev/null; then
            echo "Dependcy missing: ${i}"
            if [ "$mac" == "" ]
            then
               if [ "${i}" == "xidel" ]
               then
                  echo "Please install ${i} 0.8 _bin/xidel_0.8.4-1_amd64.deb or https://sourceforge.net/projects/videlibri/files/Xidel/Xidel%200.8.4/"
               else
                  echo "Please apt-get or yum install ${i}"
               fi         
            else
               if [ "${i}" == "xidel" ]
               then
                  echo "Please install ${i} 0.8 _bin/xidel.zip or http://www.videlibri.de/xidel.html#downloads"
               else
                  echo "Please brew install ${i}"
               fi         
            fi
            echo ""
            exit 1
        fi
    done
}


##################### Program Entry Point #####################
# Set some program global variables
mac=`uname -a | grep -i darwin`

if [ "$mac" == "" ]
then
   # using wine to run an old version since the latest doesn't work with younow
#   rtmp="wine ./_bin/rtmpdump.exe"
   rtmp=rtmpdump
fi

# Locations for working files and final videos
mkdir -p ./_temp 2>/dev/null
mkdir -p ./videos 2>/dev/null

# Verify all of the helper tools are available, so the script doesn't crash later.
checkDependencies

# Start the interactive menu
mainProgramLoop
echo "Thanks for using the downloader tool. Have a nice day."

# clean up all the temp files.
rm -rf ./_temp/ 2>/dev/null 
###############################################################
