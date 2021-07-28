if [ $# -ne 2 ]
then
 echo -e "\nUsage: $0 ORACLE_SID UserName\n"
 exit 1;
fi

. ~/.bashrc

export ORACLE_SID=$1
export UserName=$2

if [ -f "/tmp/kill_${ORACLE_SID}_${UserName}.sql" ]
then
 rm /tmp/kill_${ORACLE_SID}_${UserName}.sql
fi

sqlplus -S -L / as sysdba << ENDSQL
 set hea off
 set pagesize 100
 spool /tmp/kill_${ORACLE_SID}_${UserName}.sql
 select 'alter system kill session '''||sid||','||serial#||'''immediate ;' from v\$session where username like upper('${UserName}%');
 spool off
ENDSQL

clear
read -p "Kill the sessions for ${UserName}* in ${ORACLE_SID}? [y/n] " killnow

if [ "${killnow}" == "y" ]
then
 echo "exit;" >> /tmp/kill_${ORACLE_SID}_${UserName}.sql
 sqlplus -S -L / as sysdba @/tmp/kill_${ORACLE_SID}_${UserName}.sql

elif [ "${killnow}" == "n" ]
then 
 echo "Kill session command outfile '/tmp/kill_${ORACLE_SID}_${UserName}.sql'"
 
fi
