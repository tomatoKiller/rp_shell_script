#!/bin/bash

# Author: Wu Runpeng
# Create Date: 2018-08-16
# Modified Date: 2018-08-20 10:00

# description: 
# 本脚本兼容crontab的配置语法，用来替代crontab执行任务的定时调度

# install:
# sh rp_crontab.sh install_path
# edit the ${install_path}/rp_crontab/rp_crontab.conf
# cd ${install_path}
# nohup sh rp_crontab.sh >/dev/null 2>&1 &

INSTALL_PATH="."
MAIN_PATH="${INSTALL_PATH}/rp_crontab"
CONFIG_FILE="${MAIN_PATH}/rp_crontab.conf"
LOG_FILE="${MAIN_PATH}/rp_crontab.log"

FORMAT=""


install() {
    INSTALL_PATH=$1
    mkdir -p $MAIN_PATH
    touch $CONFIG_FILE
    exit 0
}

LOG_DEBUG() {
    time=`date "+%Y-%m-%d %H:%M:%S"`
    # echo "$time:  $1"
    return
}

LOG_ERROR() {
    time=`date "+%Y-%m-%d %H:%M:%S"`
    echo "$time:  $1"
}

if [[ $1 == "install" ]]; then
    install .
fi

# return: 0: can't run;  1: can run
task_can_run() {
    local task_name=$1
    local format_cate=$2  #格式类型
    local time_unit=$3      #当前处理的时间粒度：分、时、日、月、年

    local last_exec_time=`cat $task_name`
    local last_exec_seconds=`date -d "$last_exec_time" +%s`
    local now_seconds=`date +%s`
    
    LOG_DEBUG "task_can_run : $task_name $format_cate $FORMAT $time_unit"
    LOG_DEBUG "task_can_run : FORMAT length=${#FORMAT[@]}"

    if [[ $format_cate == 0 ]]; then
        return 1
    elif [[ $format_cate == 1 ]]; then
        # 按周期执行的任务
        local time_diff=-1
        case $time_unit in 
        1)
            time_diff=`expr \( $now_seconds - $last_exec_seconds \) \/ 60`
        ;;
        2)
            time_diff=`expr \( $now_seconds - $last_exec_seconds \) \/ 3600`
        ;;
        3)
            last_day=`date -d "$last_exec_time" +%d`
            curr_day=`date +%d`
            time_diff=`expr  $curr_day - $last_day `
        ;;
        4)
            last_month=`date -d "$last_exec_time" +%m`
            curr_month=`date +%m`
            time_diff=`expr  $curr_month - $last_month `
        ;;
        5)
            last_year=`date -d "$last_exec_time" +%Y`
            curr_year=`date +%Y`
            time_diff=`expr \( $curr_year - $last_year \) \/ 60`
        ;;
        esac

        if [[ $time_diff -lt $FORMAT ]]; then 
            # 当前还没达到需要执行的周期，直接返回0
            return 0
        fi
    elif [[ $format_cate == 2 ]]; then  
        # 定时执行的任务
        local curr_point=-1  #当前时间点
        # local last_point=-1

        local run_twice=0   #该变量用来防止同一分钟内多次运行同一个程序

        if [[ `expr $now_seconds - $last_exec_seconds` -lt 60 ]]; then 
            run_twice=1
        fi

        case $time_unit in 
        1)
            curr_point=`date +%M`
        ;;
        2)
            curr_point=`date +%H`
            # last_point=`date -d "$last_exec_time" +%H`
            # if [[ `expr $now_seconds - $last_exec_seconds` -lt 3600 ]]; then 
            #     run_twice=1
            # fi
        ;;
        3)
            curr_point=`date +%d`
            # last_point=`date -d "$last_exec_time" +%d`

            # if [[ `expr $now_seconds - $last_exec_seconds` -lt $((3600*24)) ]]; then 
            #     run_twice=1
            # fi

            local ttt=`expr $now_seconds - $last_exec_seconds`
            # LOG_DEBUG "$now_seconds $last_exec_seconds $ttt $run_twice"
        ;;
        4)
            curr_point=`date +%m`
            # last_point=`date -d "$last_exec_time" +%m`
            # if [[ `expr $now_seconds - $last_exec_seconds` -lt $((3600*24*30)) ]]; then 
            #     run_twice=1
            # fi
        ;;
        5)
            curr_point=`date +%Y`
            # last_point=`date -d "$last_exec_time" +%Y`
            # if [[ `expr $now_seconds - $last_exec_seconds` -lt $((3600*24*365)) ]]; then 
            #     run_twice=1
            # fi
        ;;
        esac

        

        curr_point=`expr $curr_point + 0`   #转换为数字
        # last_point=`expr $last_point + 0`   #转换为数字

        LOG_DEBUG "FORMAT=$FORMAT"
        LOG_DEBUG "curr_point=$curr_point,  run_twice=$run_twice"

        local flag=0
        for point in ${FORMAT[@]}; do 
            # 如果当前时间点就是配置的需要执行的时间点，并且上次执行任务对应的时间点 和当前时间不在同一个时间点
            if [[ $point == $curr_point && $run_twice == 0 ]]; then
                flag=1
                break
            fi
        done
        if [[ $flag == 0 ]]; then 
            # 当前还没达到需要执行的时间点，直接返回
            return 0
        fi
    fi 
    return 1
}

handle_task() {
    local task_name=$1
    local minute=$2
    local hour=$3
    local day=$4
    local month=$5
    local year=$6
    local command=$7

    LOG_DEBUG "handle_task: $task_name $minute $hour $day $month $year $command \n"

    local now=`date "+%Y-%m-%d %H:%M:%S"`
    if [[ ! -e $task_name ]]; then 
        LOG_DEBUG "first time exec"
        echo "1970-01-01 00:00:00" > $task_name
    fi

    local format_cate=-1

############# minute parse

    handle_format "$minute"

    format_cate=$?
    if [[ $format_cate == 255 ]]; then
        LOG_ERROR "format error for minute[$minute]"
        return
    fi

    task_can_run "$task_name" $format_cate 1
    if [[ $? == 0 ]]; then 
        LOG_ERROR "task_can_run faield[failed format: minute]"
        return 
    fi

############# hour parse

    handle_format "$hour"

    format_cate=$?
    if [[ $format_cate == 255 ]]; then
        LOG_ERROR "format error for hour[$hour]"
        return
    fi

    task_can_run "$task_name" $format_cate 2
    if [[ $? == 0 ]]; then 
        LOG_ERROR "task_can_run faield[failed format: hour]"
        return 
    fi

############# day parse

    handle_format "$day"

    format_cate=$?
    if [[ $format_cate == 255 ]]; then
        LOG_ERROR "format error for day[$day]"
        return
    fi
    
    task_can_run "$task_name" $format_cate 3
    if [[ $? == 0 ]]; then 
        LOG_ERROR "task_can_run faield[failed format: day]"
        return 
    fi

############# month parse

    handle_format "$month"

    format_cate=$?
    if [[ $format_cate == 255 ]]; then
        LOG_ERROR "format error for month[$month]"
        return
    fi

    task_can_run "$task_name" $format_cate 4
    if [[ $? == 0 ]]; then 
        LOG_ERROR "task_can_run faield[failed format: month]"
        return 
    fi

############# year parse

    handle_format "$year"

    format_cate=$?
    if [[ $format_cate == 255 ]]; then
        LOG_ERROR "format error for year[$year]"
        return
    fi

    task_can_run "$task_name" $format_cate 5
    if [[ $? == 0 ]]; then 
        LOG_ERROR "task_can_run faield[failed format: year]"
        return 
    fi


    echo $now > $task_name

    eval "nohup $command &"


    LOG_DEBUG "exec $command"
    echo "$now: exec $command" >> $LOG_FILE

    
}


# return: 0:*, 1: */x, 2: 1,2,3.. , 255: error
handle_format() {
    origin=$1
    time_string=""

    LOG_DEBUG "format=$origin"

    if [[ $origin == "*" ]]; then
        FORMAT=""
        return 0
    elif echo $origin | grep "\*/"; then 
        FORMAT=${origin:2:${#origin}}

        if ! echo $FORMAT | grep "^[[:digit:]]*$"; then
            LOG_ERROR "error Format[$origin]"
            return 255
        fi

        FORMAT=`expr $FORMAT + 0`   #转换为数字


        return 1

    elif echo $origin | tr -d "[, ]" | grep "^[[:digit:]]*$"; then
        # 匹配多个数字逗号分隔的情况
        time_string=$origin
    elif echo $origin | tr -d "[\-/ ]" | grep "^[[:digit:]]*$"; then
        # 匹配 2-8/2 这种情况
        if ! echo $origin | grep "/"; then 
            origin="${origin}/1"
        fi
        origin=`echo $origin | tr -d "[ ]"`
        left_part=${origin%%/*}
        right_part=${origin##*/}
        begin_time=${left_part%%-*}
        end_time=${left_part##*-}
        time_string=""

        if ! echo $right_part | grep "^[[:digit:]]*$"; then
            LOG_ERROR "error Format[$origin]"
            return 255
        fi

        if ! echo $begin_time | grep "^[[:digit:]]*$"; then
            LOG_ERROR "error Format[$origin]"
            return 255
        fi

        if ! echo $end_time | grep "^[[:digit:]]*$"; then
            LOG_ERROR "error Format[$origin]"
            return 255
        fi

        # LOG_ERROR $left_part $right_part $begin_time $end_time

        local i=$begin_time
        while [ $i -le $end_time ]; do
                time_string="${time_string},$i"
                # echo $right_part
                i=`expr $i + $right_part`
        done

        time_string=${time_string:1:${#time_string}}

        LOG_DEBUG "time_string=$time_string"
    else
        LOG_ERROR "error Format[$origin]"
        return 255
    fi

    local OLD_IFS=$IFS
    IFS=","
    FORMAT=($time_string)
    LOG_DEBUG "FORMAT LENGTH=${#FORMAT[@]}"
    IFS=$OLD_IFS

    return 2

}


while true; do 
    OLD_IFS=$IFS
    IFS=$'\n'

    for line in `cat $CONFIG_FILE`; do 
        if [[ ${line:0:1} == "#" ]]; then 
            LOG_DEBUG "$line is droped"
            continue
        fi
        INNER_OLD_IFS=$IFS
        IFS=" "

        read -a arr <<< $line
        minute=${arr[0]}
        hour=${arr[1]}
        day=${arr[2]}
        month=${arr[3]}
        year=${arr[4]}
        command=""
        for((i=5; i < ${#arr[@]};i++)); do 
            command=$command${arr[$i]}" "
        done
        # LOG_DEBUG $command

        task_name=`echo "$line"|tr -d "[ \t]" |md5sum|head -c 32`
        task_name="${MAIN_PATH}/${task_name}.task"
        

        handle_task "$task_name" "$minute" "$hour" "$day" "$month" "$year" "$command"

        IFS=$INNER_OLD_IFS
    done
    IFS=$OLD_IFS
    sleep 1
done

