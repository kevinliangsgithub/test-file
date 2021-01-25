#!/bin/bash

# 集群巡检脚本 inspection_cluster.sh
# 脚本会创建inspect目录
# 脚本生成的10个输出文件放在inspect目录内
# 脚本需放在/root/datapipeline/目录下执行

. manifest.sh

date=`date +%Y-%m-%d`
dateH=`date +%Y-%m-%d-%H:%M:%S`
zk_id=`docker ps |grep zk |awk '{print $1}'`
mysql_id=`docker ps |grep mysql |awk '{print $1}'`
webservice_id=`docker ps |grep webservice |awk '{print $1}'`
manager_ip=`cat manifest.sh |grep NODE2 |awk -F '=' '{print $2}'`
mysql_passwd="Datapipeline123"
renwu_delete=$DP_SCRIPT_DIR/inspect/renwu.delete
renwu_now=$DP_SCRIPT_DIR/inspect/renwu.now
topic_all=$DP_SCRIPT_DIR/inspect/topic.all
bingfa_list=$DP_SCRIPT_DIR/inspect/bingfa.list
datasource_id=$DP_SCRIPT_DIR/inspect/datasource_id
datasource_count=$DP_SCRIPT_DIR/inspect/datasource_count
datadest_id=$DP_SCRIPT_DIR/inspect/datadest_id
datadest_count=$DP_SCRIPT_DIR/inspect/datadest_count
topic_delete=$DP_SCRIPT_DIR/inspect/topic.delete
inspection_log=$DP_SCRIPT_DIR/inspect/inspection.log
dir=$DP_SCRIPT_DIR/inspect
run_really=`cat manifest.sh |grep DP_SCRIPT_DIR |wc -l`

# 判断manifest.sh脚本的DP_SCRIPT_DIR变量
if [ $run_really -eq 0 ];then
    echo -e "\033[31m ### 脚本退出! ### \033[0m"
    echo -e "\033[31m ### manifest.sh脚本内没有DP_SCRIPT_DIR变量，请检查 ### \033[0m"
    exit
fi
# 判断inspect目录是否存在
if [ ! -d $dir ];then
    mkdir $DP_SCRIPT_DIR/inspect
fi

echo -e "$dateH" > $inspection_log
# 获取现有任务ID
task_total3() {
docker exec -it $webservice_id curl $manager_ip:2222/dptasks |sed 's/"//g;s/,/\n/g;s/]//g;s/\[//g;$a n' |grep -v 'n' 1> $renwu_now 2>/dev/null
task_total=`cat $renwu_now |wc -l`
echo -e "\033[32m### 现有任务共 = $task_total 个 ###\033[0m"
echo -e "### 现有任务共 = $task_total 个 ###" >> $inspection_log
}

# 获取启动中和暂停中的任务数量
running_paused_total3() {
for i in `cat $renwu_now`
do
    RUNNING=`docker exec -it $webservice_id curl $manager_ip:2222/dptasks/$i/status |grep RUNNING |wc -l`
    if [ $RUNNING -eq 1 ];then
        x=0
        x=$(($x + 1))
        let r_n+=$x
    else
        y=0
        y=$(($y + 1))
        let p_n+=$y
    fi
done
echo -e "\033[32m### 启动中的任务 = $r_n 个 ###\033[0m"
echo -e "### 启动中的任务 = $r_n 个 ###" >> $inspection_log
echo -e "\033[32m### 暂停中的任务 = $p_n 个 ###\033[0m"
echo -e "### 暂停中的任务 = $p_n 个 ###" >> $inspection_log
}

# 获取已删除任务ID
delete_task() {
docker exec $mysql_id mysql -uroot -p$mysql_passwd dp-thrall -e "select data_pipeline_id from data_pipelines where active_status=0;" |grep -v 'id' 1> $renwu_delete 2>/dev/null
delete_task=`cat $renwu_delete |wc -l`
echo -e "\033[32m### 已删除任务共 = $delete_task 个 ###\033[0m"
echo -e "### 已删除任务共 = $delete_task 个 ###" >> $inspection_log
}

# kafka-topic总数
topic_total() {
docker exec -it $zk_id kafka-topics --list --zookeeper $zk_id 1> $topic_all 2>/dev/null
topic_total=`cat $topic_all |wc -l`
echo -e "\033[32m### kafka topic数量共 = $topic_total 个 ###\033[0m"
echo -e "### kafka topic数量共 = $topic_total 个 ###" >> $inspection_log
}

# 已废弃topic的总数
topic_delete() {
for i in `cat $renwu_delete`
do
    cat $topic_all |grep -w "dptask_$i" >> $topic_delete
    cat $topic_all |grep -w "v2_dptask_$i" >> $topic_delete
done
topic_delete_total=`cat $topic_delete |wc -l`
echo -e "\033[32m### 已废弃topic数量共 = $topic_delete_total 个 ###\033[0m"
echo -e "### 已废弃topic数量共 = $topic_delete_total 个 ###" >> $inspection_log
}

# kafka 数据目录大小
kafka_du() {
kafka_du=`du -sh $DP_DIR/datapipeline/kafka_data`
echo -e "\033[32m### kafka 数据目录大小 = $kafka_du ###\033[0m"
echo -e "### kafka 数据目录大小 = $kafka_du ###" >> $inspection_log
}

# 获取任务读写并发
renwu() {
for i in `cat $renwu_now`
do 
    docker exec $mysql_id mysql -uroot -p$mysql_passwd dp-thrall -e "select json_extract(config,'$.dataSourceConfig.concurrencyLevel') as src_bingxing,json_extract(config,'$.destinationConfigs[0].concurrencyLevel') as sink_bingxing from data_pipelines where data_pipeline_id=$i;" 1>> $bingfa_list 2>/dev/null
done
}

# 读并发
read1() {
read1=`cat $bingfa_list |awk '{sum1+=$1} END {print sum1}'`
echo -e "\033[32m### 读取并发总数为 = $read1 ###\033[0m"
echo -e "### 读取并发总数为 = $read1 ###" >> $inspection_log
}

# 写并发
writh1() {
writh1=`cat $bingfa_list |awk '{sum1+=$2} END {print sum1}'`
echo -e "\033[32m### 写入并发总数为 = $writh1 ###\033[0m"
echo -e "### 写入并发总数为 = $writh1 ###" >> $inspection_log
}

# 现有数据源ID
datasource() {
docker exec $mysql_id mysql -uroot -p$mysql_passwd dp-thrall -e "select data_source_id from data_sources where active_status=1;" |grep -v 'id' 1> $datasource_id 2>/dev/null
datasource_total=`cat $datasource_id |wc -l`
echo -e "\033[32m### 数据源数量共 = $datasource_total 个 ###\033[0m"
echo -e "### 数据源数量共 = $datasource_total 个 ###" >> $inspection_log
# 数据源多少张表
for n in `cat $datasource_id`
do 
    echo "数据源：$n" 1>> $datasource_count 2>/dev/null
    docker exec $mysql_id mysql -uroot -p$mysql_passwd dp-thrall -e "select count(name) as table_count from source_schemas_v3 where data_source_id=$n;" 1>> $datasource_count 2>/dev/null
done
}

# 现有目的地ID
datadest() {
docker exec $mysql_id mysql -uroot -p$mysql_passwd dp-thrall -e "select data_destination_id from data_destinations where active_status=1;" |grep -v 'id' 1> $datadest_id 2>/dev/null
datadest_total=`cat $datadest_id |wc -l`
echo -e "\033[32m### 目的地数量共 = $datadest_total 个 ###\033[0m"
echo -e "### 目的地数量共 = $datadest_total 个 ###" >> $inspection_log
# 目的地多少张表
for d in `cat $datadest_id`
do 
    echo "目的地：$d" 1>> $datadest_count 2>/dev/null
    docker exec $mysql_id mysql -uroot -p$mysql_passwd dp-thrall -e "select count(name) as table_count from destination_schemas_v3 where data_destination_id=$d;" 1>> $datadest_count 2>/dev/null
done
}

# 节点名称
node() {
node=`cat manifest.sh |grep SERVICE_USER |awk -F '=' '{print $2}'`
echo -e "\033[32m### 用户标识符名称为 = $node ###\033[0m"
echo -e "### 用户标识符名称为 = $node ###" >> $inspection_log
}

# 系统版本
release() {
release=`cat /etc/redhat-release` 
echo -e "\033[32m### 系统版本为 = $release ###\033[0m"
echo -e "### 系统版本为 = $release ###" >> $inspection_log
}

# 系统内存
free_total() {
free_total=`free -g |awk NR==2'{print $2}'`
free_available=`free -g |awk NR==2'{print $7}'`
echo -e "\033[32m### 系统内存大小为 = $free_total G ###\033[0m"
echo -e "### 系统内存大小为 = $free_total G ###" >> $inspection_log
echo -e "\033[32m### 系统内存当前可用 = $free_available G ###\033[0m"
echo -e "### 系统内存当前可用 = $free_available G ###" >> $inspection_log
}

# 系统CPU
cpu_ls() {
cpu=`lscpu |grep "CPU(s):" |awk NR==1'{print $2}'`
echo -e "\033[32m### 系统cpu核数为 = $cpu 核 ###\033[0m"
echo -e "### 系统cpu核数为 = $cpu 核 ###" >> $inspection_log
}

# 系统负载
load() {
load_average=`uptime |awk -F 'load average:' '{print $2}'`
echo -e "\033[32m### 系统当前负载情况 = $load_average ###\033[0m"
echo -e "### 系统当前负载情况 = $load_average ###" >> $inspection_log
}

# DP版本信息
version() {
dp_version=`cat manifest.sh |grep "export DP_DATA_SYSTEM_VERSION" -C 1`
echo -e "\033[32m### DP版本信息: ###\033[0m
$dp_version"
echo -e "### DP版本信息: ###
$dp_version" >> $inspection_log
}

# 系统硬盘使用量
df_h() {
echo -e "\033[32m### 磁盘使用情况: ###\033[0m"
df -h |grep dev
echo -e "### 磁盘使用情况: ###" >> $inspection_log
df -h |grep dev >> $inspection_log
}

# 函数调用输出结果
echo -e "\033[36m### 巡检脚本统计信息 ###\033[0m"
echo -e "### 巡检脚本统计信息 ###" >> $inspection_log
task_total3
running_paused_total3
datasource
datadest
delete_task
renwu
topic_total
topic_delete
kafka_du
read1
writh1
node
release
free_total
load
cpu_ls
version
df_h

echo -e "\033[36m### 脚本生成的10个输出文件放在inspect目录内 ###\033[0m"
echo -e "### 脚本生成的10个输出文件放在inspect目录内 ###" >> $inspection_log

echo -e "\033[36m### 已打包inspect目录为: inspect-$date.tar.gz ###\033[0m"
echo -e "### 已打包inspect目录为: inspect-$date.tar.gz ###" >> $inspection_log
tar czvf inspect-$date.tar.gz inspect > /dev/null 2>&1

# 备份输出的10个文件，时间戳后缀
mv $renwu_delete $renwu_delete-$dateH
mv $renwu_now $renwu_now-$dateH
mv $topic_all $topic_all-$dateH
mv $bingfa_list $bingfa_list-$dateH
mv $datasource_id $datasource_id-$dateH
mv $datasource_count $datasource_count-$dateH
mv $datadest_id $datadest_id-$dateH
mv $datadest_count $datadest_count-$dateH
mv $topic_delete $topic_delete-$dateH
mv $inspection_log $inspection_log-$dateH  

