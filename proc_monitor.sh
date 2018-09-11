#!/bin/bash

# Author: Wu Runpeng
# Create Date: 2018-08-16
# Modified Date: 2018-08-20 10:00

# 脚本功能：通过名字来监控服务进程的状态，如果进程不在了，则重新启动进程，并将日志写入db。
# use:  ./proc_monitor.sh loop 3 service_path "sh loop.sh"


LOG_DB_HOST="127.0.0.1"
LOG_DB_PORT=3306
LOG_DB_USER="root"
LOG_DB_PASS="root123456"

#常量定义
MAX_RESTART_NUM=10
LOG_DB_NAME="moxinmanager"
LOG_DB_TABLE="service_monitor"
LOG_DB_LOG_TABLE="service_restart_log"
LOG_DB_MONI_STATUS="monitor_serv_status"


:<<EOF
如何判断监控程序和被监控程序的存活
1. 通过$LOG_DB_MONI_STATUS 的时间戳来判断 监控程序的存活状况
2. 如果监控程序存活，则通过$LOG_DB_TABLE的status字段来判断 被监控服务的状态。
3. 通过$LOG_DB_LOG_TABLE可以查看被监控服务的历史重启日志
EOF

#全局变量定义
G_PID=-1                # 当前活动进程的PID
G_SELECT_NUM_RESULT=-1

g_script_name=""
g_proc_name=""
g_interval=3            # seconds
g_work_dir=""
g_command=""


trap exit_signal_func 2

install(){
    ret=$(mysql -h ${LOG_DB_HOST} -u ${LOG_DB_USER} -p${LOG_DB_PASS} -D ${LOG_DB_NAME} --default-character-set=utf8 -e "show databases like '$LOG_DB_NAME'" );
    if [[ ! -n "$ret" ]]; then
        echo "error: mysql db $LOG_DB_NAME don't exist, please create it "
        exit 1
    fi
    mysql -h ${LOG_DB_HOST} -u ${LOG_DB_USER} -p${LOG_DB_PASS} -D ${LOG_DB_NAME} --default-character-set=utf8 < dump.sql
    exit 0
}



#description: 匹配基于进程名，因此要保证被监控进程名唯一
#return:
#   0: alive
#   1: dead

check_process_status() {
    local p_name=$1
    local pid=""

    pid=$(pgrep -if "$p_name" | head -n 1)

    if [ ${#pid} != 0 ]; then
        G_PID=$pid
        return 0
    fi

    G_PID=-1
    return 1
}

# 0: success
# 1: failed
restart_process(){

    local work_dir=$1
    local command=${*:2}

    # echo "$work_dir"
    # echo $command

    eval "cd $work_dir"

    eval " nohup $command 2>&1 & "

    local ret=0

    if [ $? -ne 0 ]; then
        ret=1
    fi 

    cd -

    return $ret
}




mysql_insert_update(){
    local sql=$1
    ret=$(mysql -h ${LOG_DB_HOST} -u ${LOG_DB_USER} -p${LOG_DB_PASS} -D ${LOG_DB_NAME} --default-character-set=utf8 -e "${sql}")
    if [[ $? != 0 ]]; then
        return 1
    fi
    
    return 0
}

mysql_select_num(){
    local sql=$1
    ret=$(mysql -h ${LOG_DB_HOST} -u ${LOG_DB_USER} -p${LOG_DB_PASS} -D ${LOG_DB_NAME} --default-character-set=utf8 -e "${sql}"  | awk 'NR>1')
    if [[ ! -n "$ret" ]]; then
        echo "sql fmt error[$sql] "
        G_SELECT_NUM_RESULT=-1
        return 1
    fi

    G_SELECT_NUM_RESULT=$ret

    return 0
}


do_exit(){
    mysql_insert_update "delete from $LOG_DB_MONI_STATUS where proc_name='$g_proc_name' and ip='$g_ip';"
    exit "$1"
}


update_proc_status(){

    local proc_id=$1

    mysql_select_num "select count(*) from $LOG_DB_TABLE where proc_name='$g_proc_name' and ip='$g_ip';"

    if [[ $G_SELECT_NUM_RESULT == 0 ]]; then
        mysql_insert_update "insert into $LOG_DB_TABLE (proc_name, proc_id, ip, status) values ('$g_proc_name',$proc_id,'$g_ip', 0);"
    else
        mysql_insert_update "update $LOG_DB_TABLE set proc_id=$proc_id, mtime=now() where proc_name='$g_proc_name' and ip='$g_ip';"
    fi
}

exit_signal_func(){
    echo "$g_script_name killed"
    mysql_insert_update "insert into $LOG_DB_LOG_TABLE (proc_name, ip, log) values ('$g_proc_name', '$g_ip', 'monitor dead[be killed]');"      
    do_exit 0
}



print(){
  echo "./monitor.sh proc_name interval work_dir command "
  echo "./monitor.sh proc_name clean"
  echo "./monitor.sh install"
  exit 1;   
}


#################################### entry point ####################################

g_ip=$(ifconfig -a|grep "eth.*" -A 3 | grep inet|grep -v 127.0.0.1|grep -v inet6|grep -v "\\-\\->"|awk '{print $2}'|sed 's/addr://g')

if [[ $# == 4 ]]; then
    g_script_name=$0
    g_proc_name=$1
    g_interval=$2  #seconds
    g_work_dir=$3
    g_command=${*:4}
elif [[ $# == 2 && $2 == "clean" ]]; then
    mysql_insert_update "delete from $LOG_DB_MONI_STATUS where proc_name='$1' and ip='$g_ip';"
    echo "clean complete"
    exit 0
elif [[ $# == 1 && $1 == "install" ]]; then
    install
else
    print
fi


#判断是否已经启动了相同名称进程的监控程序
mysql_select_num "select count(*) from $LOG_DB_MONI_STATUS where proc_name='$g_proc_name' and ip='$g_ip';"

if [[ $G_SELECT_NUM_RESULT -gt 0 ]]; then
    echo "already exist same monitor service"
    exit 0
fi

mysql_insert_update "insert into $LOG_DB_MONI_STATUS (proc_name, ip) values ('$g_proc_name', '$g_ip');"

restart_try_num=0
while true; do

    check_process_status "$g_proc_name" 

    if [[ $G_PID -ge 0 ]]; then
        restart_try_num=0
        update_proc_status $G_PID
        sleep "$g_interval"
    else
        if [[ $restart_try_num > $MAX_RESTART_NUM ]]; then
            echo "restart failed[reach max restart num. ]"
            mysql_insert_update "insert into $LOG_DB_LOG_TABLE (proc_name, ip, log) values ('$g_proc_name', '$g_ip', 'service dead, restart failed[reach max restart num.]');"
            do_exit 1
        fi

        update_proc_status -1

        if restart_process "$g_work_dir" "$g_command" ; then
            mysql_insert_update "insert into $LOG_DB_LOG_TABLE (proc_name, ip, log) values ('$g_proc_name', '$g_ip', 'service dead, restart success');"
        else
            mysql_insert_update "insert into $LOG_DB_LOG_TABLE (proc_name, ip, log) values ('$g_proc_name', '$g_ip', 'service dead, restart failed');"
        fi

        sleep 1

        ((restart_try_num++))

    fi

    #这里仅仅是为了更新监控程序状态数据记录的时间戳，作为判断是否存活的心跳
    mysql_insert_update "update $LOG_DB_MONI_STATUS set mtime=now() where proc_name='$g_proc_name' and ip='$g_ip';"
done

