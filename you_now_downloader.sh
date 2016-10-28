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

source ./you_now_moments.sh

echo "+--------------------------------------------+"
echo "|        YouNow video downloader             |"
echo "+--------------------------------------------+"
echo "|       This script helps you download       |"
echo "|   YouNow.com broadcasts and live streams   |"
echo "+--------------------------------------------+"
echo ""
echo "This script relise on several binary files located in ./_bin. You are responsible for finding these files. Apt-get or brew install them."
echo "    file: ffmpeg"
echo "    file: rtmpdump"
echo "    file: xidel"
echo "    file: wget"
echo ""
echo "Paste broadcast username below (right click - Paste) and press Enter"

function mainProgramLoop() {
    local status="running"
    while [[ "${status}" == "running" ]]; do
        echo ""
        echo "Enter username (leave blank to quit):" 
        read entered_name
        web=`echo $entered_name | grep 'younow.com'`

        if [ -z ${entered_name} ]; then
            status="exit"

        elif [ ! -z ${web} ]; then
            directDownloadMenu

        else
            userDownloadMenu "${entered_name}"
        fi
    done
}


# @param: url
function directDownloadMenu()
{
    local url=$1

    user=`echo ${url} | cut -d'/' -f4`
    broadcast_id=`echo ${url} | cut -d'/' -f5`
    user_id=`echo ${url} | cut -d'/' -f6`

    downloadVideo "${user}" "0" "${broadcast_id}"

    echo " OK! Started download in a separate window."
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
        wget --no-check-certificate -q "http://bcm.younow.com/broadcast/info/user=${user_name}" -O "./_temp/${user_name}.json"

        local user_id=`xidel -q ./_temp/${user_name}.json -e '$json("userId")'`
        local error=`xidel -q ./_temp/${user_name}.json -e '$json("errorCode")'`
        local errorMsg=`xidel -q ./_temp/${user_name}.json -e '$json("errorMsg")'`
        #echo Error code: $error

        if [ "${error}" == "101" -o ! -s ./_temp/${user_name}.json ]
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
            downloadPreviousBroadcastsMenu "${user_id}" "${user_name}"

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
        xterm -e "$rtmp -v -o ./videos/${user_name}/${filename} -r rtmp://$host$app/$stream; bash;exit" &
    else
        echo "cd `pwd` ; rtmpdump -v -o ./videos/${user_name}/${filename} -r rtmp://$host$app/$stream" > "./_temp/${filename}.command"
        chmod +x "./_temp/${filename}.command"
        open "./_temp/${filename}.command"
        rm ./_temp/${filename}.command
    fi
    echo " OK! Started recording in a separate window."
}


# @param: user_id
# @param: user_name
function downloadPreviousBroadcastsMenu()
{
    local user_id=$1
    local user_name=$2

    local ex="false"
    local idx=1
    local startTime=0
    local videos

    while [ "$ex" == "false" ]
    do
        wget --no-check-certificate -q "http://www.younow.com/php/api/post/getBroadcasts/startFrom=$startTime/channelId=${user_id}" -O "./_temp/${user_name}_json.json"
        xidel -q -e '($json).posts().media.broadcast/join((videoAvailable,broadcastId,broadcastLengthMin,ddateAired),"-")' "./_temp/${user_name}_json.json" > "./_temp/${user_name}_list.txt"
        rm ./_temp/${user_name}_json.json

        if [  -f "./_temp/${user_name}_list.txt" ]
        then
            echo -e "    ID  Length            Date               Broadcast id"
            while read line 
            do
                available=`echo $line | cut -d'-' -f1`
                broadcast_id=`echo $line|cut -d'-' -f2`
                length=`echo $line | cut -d'-' -f3`
                ddate=`echo $line | cut -d'-' -f4 | sed "s/ /_/g"`
                if [ "$available" == "1" ]
                then
                   current=""
                   printf " %4s   %5s  %26s %1s %10s \n" ${idx} ${length} ${ddate} - ${broadcast_id}
                   videos[${idx}]=${broadcast_id}
                   dates[${idx}]=`echo ${ddate}`
                   idx=$((idx + 1))
                fi
            done < "./_temp/${user_name}_list.txt"
            rm ./_temp/${user_name}_list.txt

            echo "Type comma separated numbers, \"all\" to download everything,"
            echo "\"n\" to list next 10 broadcasts or leave blank to return: "
            read input      

            if [ "$input" == "" ]
            then
                ex="true"
            elif [ "$input" == "n" ]
            then  
                startTime=$(( startTime  + 10 ))
            else
                if [ "$input" == "all" ]
                then
                    for i in `seq 1 ${#videos[@]}`
                    do
                        downloadVideo "${user_name}" "$i" "${videos[$i]}" "${dates[$i]}"
                    done
                fi

                while [ "$input" != "$current" ]
                do
                    current=`echo $input | cut -d',' -f1`
                    input=`echo $input | cut -d',' -f2-`  
                    downloadVideo "${user_name}" "${num1}" "${videos[${current}]}" "${dates[${current}]}"
                    num1=$((num1 + 1))
                done
                startTime=$(( startTime  + 10 ))
            fi 
        else
            echo " - There's nothing to show."
            ex="true"
        fi
    done
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


# Function: Download a video.
# @param: user name
# @param: video number (numeric order)
# @param: broadcast id
function downloadVideo()
{
    local user_name=$1
    local dirr=$1_$2
    local broadcast_id=$3
    local ddate=$4

    mkdir -p "./_temp/${dirr}"
    mkdir -p "./videos/${user_name}"

    wget --no-check-certificate -q "http://www.younow.com/php/api/younow/user" -O "./_temp/${dirr}/session.json"
    wget --no-check-certificate -q "http://www.younow.com/php/api/broadcast/videoPath/broadcastId=${broadcast_id}" -O "./_temp/${dirr}/rtmp.json"
    
    local session=`xidel -q ./_temp/${dirr}/rtmp.json -e '$json("session")'`
    local server=`xidel -q ./_temp/${dirr}/rtmp.json -e '$json("server")'`
    local stream=`xidel -q ./_temp/${dirr}/rtmp.json -e '$json("stream")'`
    local hls=`xidel -q ./_temp/${dirr}/rtmp.json -e '$json("hls")'`

    rm ./_temp/${dirr}/session.json
    rm ./_temp/${dirr}/rtmp.json

    if $verbose ; then
        echo "--- stream information ---"
        echo "session: $session"
        echo "  sever: $server"
        echo " stream: $stream"
        echo "    hls: $hls"
        echo "--- stream information ---"
    fi

    # find a unique file name for the download
    local file_name=$(findNextAvailableFileName ${user_name} "mkv" ${ddate})
    echo "user_name: ${user_name}"
    echo "broadcast"
    echo "broadcast_id: ${broadcast_id}"
    echo "mkv"
    echo "file_name: ${file_name}"

    # Execute the command
    if [ "$mac" == "" ] 
    then
        if [[ "$hls" != "" ]]; then
            xterm -e "ffmpeg -i \"$hls\"  -c:v copy \"./videos/${user_name}/${file_name}\" ;bash;exit" & 
        else
            xterm -e "$rtmp -v -o \"./videos/${user_name}/${file_name}\" -r \"$server$stream?sessionId=$session\" -p \"http://www.younow.com/\";bash;exit" &
        fi
    else
        if [[ "$hls" != "" ]]; then
            echo "cd `pwd`; ffmpeg -i \"$hls\"  -c copy \"./videos/${user_name}/${file_name}\" ; read something "  > "./_temp/${file_name}.command"
        else
            echo "cd `pwd`; rtmpdump -v -o \"./videos/${user_name}/${file_name}\" -r \"$server$stream?sessionId=$session\" -p \"http://www.younow.com/\"; read something" > "./_temp/$filename.command" 
        fi
        
        chmod +x "./_temp/${file_name}.command"
        open "./_temp/${file_name}.command"
        rm ./_temp/${file_name}.command
    fi
}


function checkDependencies()
{
    if [ "$mac" == "" ]; then
        dependencies=( "xidel" "wget" "ffmpeg")
    else
        dependencies=( "rtmpdump" "xidel" "wget" "ffmpeg")
    fi

    for i in "${dependencies[@]}"
    do
        :
        if ! hash ${i} 2>/dev/null; then
            echo "Dependcy missing: ${i}"
            echo "Please ensure all dependencies are on the PATH before launching the application."
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
   rtmp="wine ./_bin/rtmpdump.exe"
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
