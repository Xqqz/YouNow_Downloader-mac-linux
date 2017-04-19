#!/bin/bash
mac=`uname -a | grep -i darwin`

declare -a moments # bash don't support mutlideminsional arrays. use a row/ columm offset approach instead.
declare moments_count
columnsM=5
id=44

# Handle building the menu and user inputs for displaying the broadcasts avialable
# and allowing the user to download specific broadcasts.
#
# @param: user name
# @param: user id
function downloadPreviousBroadcastsMenu()
{
    local user_name=$1
    local user_id=$2
    local ex="false"

    wget --no-check-certificate -q "https://www.younow.com/php/api/moment/profile/channelId=${user_id}/createdBefore=0/records=50" -O "./_temp/${user_name}_broadcast.json"
    parseBroadcastJson "./_temp/${user_name}_broadcast.json"
    rm ./_temp/${user_name}_broadcast.json 

    while [ "$ex" == "false" ]; do
        displayUserBroadcasts $user_name

        echo "Enter the ID to download broadcast."
        read input_broadcast

        if [ "$input_broadcast" == "" ]; then
            ex="true"
        else
            echo " "
            broadcast_id=${moments[ $[ ${input_broadcast} * ${columnsM} + 1 ] ]}

            ddate=${moments[ $[ ${input_broadcast} * ${columnsM} + 2 ] ]}
#            
#            local inner_ex="false"
#            while [ "$inner_ex" == "false" ]; do
#                echo "Type comma separated numbers, \"all\" to download everything."
#                read input_moment
#                if [ "$input_moment" == "" ]; then
#                    inner_ex="true"
#
#                else
#                    moments_to_download=( )
#                    if [ "$input_moment" == "all" ]; then
#                        IFS=', ' read -r -a moments_to_download <<< "${moments[ $[ ${input_broadcast} * ${columnsM} + 4 ] ]}"
#                    else
#                        IFS=', ' read -r -a moments_to_download <<< "${input_moment}"
#                    fi
#                    IFS=' '                    
#
#                    for moment_id in ${moments_to_download[@]}; do
##                        echo "downloadMoment <$user_name> <$broadcast_id> <$moment_id>"
#                        downloadMoment ${user_name} ${broadcast_id} ${moment_id}
#                    done
#                fi
#            done
            downloadVideo ${user_name} ${input_broadcast} ${broadcast_id} ${ddate}
        fi
    done
}

# Display a selection ID along with the broadcast id and moment count
# that are available to be explored by the user.
#
# @param: user name
# @param(global): moments
# @param(global): moments_count
function displayUserBroadcasts() 
{
    printf "Broadcasts Available for $user_name \n"
    printf "    ID    Broadcast id              Date           Moment count"
    local counter="0"
    while [ $counter -lt "${moments_count}" ]
    do
           printf "  %4s    %10s        %10s      %3s \n" ${moments[$[ $counter * ${columnsM} + 0 ]]} ${moments[$[ $counter * ${columnsM} + 1 ]]} ${moments[$[ $counter * ${columnsM} + 2 ]]} ${moments[$[ $counter * ${columnsM} + 3 ]]}		
        counter=$[$counter + 1]
    done
}

# Download information about the user's moments from the server. Make this information
# available to the moments menuing system via a global variable. (Because bash does not
# support returning an array from a function.)
#
# @param: moments json file
# @return(global -> moments): Array of details about the available moments
# @return(gloabl -> moments_count): The number of broadcasts with available moments to be downloaded
function parseBroadcastJson() 
{
    local broadcast_json_file=$1
    unset moments   
    local counter="0"
    local index="1"

    ############# read the moment information retrieved from the server #############
    local broadcast_ids=$(xidel -q -e '($json).items()/join((broadcastId),"-")' "./$broadcast_json_file" | tr "\n" " ")
    broadcast_ids=( $broadcast_ids )

    local ddate=$(xidel -q -e '($json).items()/join((created),"-")' "./$broadcast_json_file" | tr "\n" " ")
    ddate=( $ddate )

    ############# for each broadcast #############
    while [ $counter -lt "${#broadcast_ids[@]}" ]
    do
        ############# gather up details about this broadcast's moments #############
        moment_index=$[${counter} +1]
        broadcast_moment_ids=$(xidel -q -e '($json).items('${moment_index}').momentsIds()' "./$broadcast_json_file" | tr "\n" " ")
        broadcast_moment_ids=( $broadcast_moment_ids )
        broadcast_moment_count="${#broadcast_moment_ids[@]}"
        
#        if [ "${broadcast_moment_count}" -ne 0 ]
#        then
            # four entries per broadcast
            moments[$[ ${index} * ${columnsM} + 0 ]]="${index}"
            moments[$[ ${index} * ${columnsM} + 1 ]]="${broadcast_ids[$counter]}"
            if [ "$mac" == "" ]
            then
                moments[$[ ${index} * ${columnsM} + 2 ]]="`date -d @${ddate[$counter]} +%h_%d_%G_%T 2>/dev/null`"
            else
                moments[$[ ${index} * ${columnsM} + 2 ]]="`date -r ${ddate[$counter]} +%h_%d_%G_%T 2>/dev/null`"
            fi
            moments[$[ ${index} * ${columnsM} + 3 ]]="${broadcast_moment_count}"
            moments[$[ ${index} * ${columnsM} + 4 ]]=$(IFS=, ; echo "${broadcast_moment_ids[*]}")
            index=$[$index + 1]
 #       fi
        counter=$[$counter + 1]
    done
    moments_count=${index}
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

    wget --no-check-certificate -q "http://www.younow.com/php/api/broadcast/videoPath/broadcastId=${broadcast_id}" -O "./_temp/${dirr}/rtmp.json"
        
    local session=`xidel -q ./_temp/${dirr}/rtmp.json -e '$json("session")'`
    local server=`xidel -q ./_temp/${dirr}/rtmp.json -e '$json("server")'`
    local stream=`xidel -q ./_temp/${dirr}/rtmp.json -e '$json("stream")'`
    local hls=`xidel -q ./_temp/${dirr}/rtmp.json -e '$json("hls")'`

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
#    echo "user_name: ${user_name}"
#    echo "broadcast"
#    echo "broadcast_id: ${broadcast_id}"
#    echo "mkv"
    echo "file_name: ${file_name}"

    # Execute the command
    if [ "$mac" == "" ] 
    then
        if [[ "$hls" != "" ]]; then
            xterm -e "ffmpeg -i \"$hls\"  -c:v copy \"./videos/${user_name}/${file_name}\" ;exit" & 
        else
            xterm -e "$rtmp -v -o \"./videos/${user_name}/${file_name}\" -r \"$server$stream?sessionId=$session\" -p \"http://www.younow.com/\";exit" &
        fi  
    else
        if [[ "$hls" != "" ]]; then
            echo "cd `pwd`; ffmpeg -i \"$hls\"  -c copy \"./videos/${user_name}/${file_name}\""  > "./_temp/${file_name}.command"
        else
            echo "cd `pwd`; rtmpdump -v -o \"./videos/${user_name}/${file_name}\" -r \"$server$stream?sessionId=$session\" -p \"http://www.younow.com/\"" > "./_temp/$filename.command" 
        fi
    
        chmod +x "./_temp/${file_name}.command"
        open "./_temp/${file_name}.command"
#        rm ./_temp/${file_name}.command
    fi
}


