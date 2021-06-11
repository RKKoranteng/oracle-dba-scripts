# author : Richard Koranteng (rkkoranteng.com)
# date   : 12/15/2020
# desc   : used for nightly schema level refresh ... EDIT LINES 21-32 AS PER ENVIRONMENT
# usage  : ./daily-refresh.sh

source /home/oracle/.bashrc
echo $PATH
# check syntax
if [ $# -ne 0 ]
then
  echo -e "\n================================================================================"
  echo -e "\nSyntax error"
  echo -e "\nUsage: $0"
  echo -e "\n================================================================================"
  exit 1;
fi

echo "STARTING dailyRefresh: `date`"

# declare variables. Change as needed
export ORACLE_SID=testdb
sourceSID='proddb'
prod='prodsrv'
schemaName='APPSCHEMA'
devUserName='DEVUSER'
expPath='/backup/DATAPUMP'
impDir=REFRESH
impPath='/backup/REFRESH'
getUserDDL='/tmp/budgetgetUserDDL.sql'
createUser='/tmp/budgetcreateUser.sql'
failMessage="DB Refresh Failed"
emails="address@email.com"

# get yesterday date format
 # get and split date
year=`date +%y`
month=`date +%m`
day=`date +%d`

 # avoid octal mismatch
if (( ${day:0:1} == 0 )); then day=${day:1:1}; fi
if (( ${month:0:1} == 0 )); then month=${month:1:1}; fi

 # calc
day=$((day-1))
if ((day==0)); then
 month=$((month-1))

 if ((month==0)); then
  year=$((year-1))
  month=12
 fi

 last_day_of_month=$((((62648012>>month*2&3)+28)+(month==2 && y%4==0)))
 day=$last_day_of_month
fi

 # format result
if ((day<10)); then day="0"$day; fi
if ((month<10)); then month="0"$month; fi
yesterday="$month$day$year"
echo "Yesterday was $yesterday"

# declare backup zip file
gbackupGZ=${sourceSID}.${yesterday}_*.dmp.gz
if (ssh oracle@${prod} ls ${expPath}/${gbackupGZ});
  then

  # check db availability
  psCount=`ps -ef | grep smon | grep -v 'grep' | grep $ORACLE_SID | wc -l`

  if [ "$psCount" -gt 0 ]
  then
   openMode=`sqlplus -L / as sysdba << ENDSQL
   set feedback off
   set hea off pages 0
   set echo off
   set pagesize 500
   set linesize 500
   set long 99999999
   set newpage none
   column open_mode format a50
   select open_mode from v\\$database;
   exit;
  ENDSQL`
  fi
  echo $openMode
  #if [ "$openMode" != "READ WRITE" ]
  #then
  # echo -e "\nError: Database '${ORACLE_SID}' is not available for DB refresh.\n"
  #else

  echo "Copying backup file from Production Server: `date`"
  # copy and extract zipped dump file from prod host
   backupGZ=`ssh oracle@${prod} ls -t ${expPath}/${gbackupGZ} | head -1 `
   scp oracle@${prod}:${backupGZ} ${impPath}
   fdmpFile=`echo $backupGZ | sed 's/.gz//'`
   dmpFile=$(basename "${fdmpFile}")
   gunzip -c $impPath/${dmpFile}.gz > $impPath/$dmpFile

   # generate user drop + creation DDL script sql script
   if [ -f "$createUser" ]
   then
    rm -fr $createUser
   fi

   touch $createUser

   checkUserExist=`sqlplus -S -L / as sysdba << ENDSQL
   set feedback off
   set hea off pages 0
   set echo off
   set pagesize 500
   set linesize 500
   set long 99999999
   set newpage none
   select count(username) from dba_users where username='${schemaName}';
   exit;
ENDSQL`

   if [ "$checkUserExist" -eq 1 ]
   then
    sqlplus -S -L / as sysdba << ENDSQL
    set feedback off
    set hea off pages 0
    set echo off
    set pagesize 500
    set linesize 500
    set long 9999999
    set pages 0
    spool ${getUserDDL}
    select stragg(dbms_metadata.get_ddl('USER','${schemaName}')) || ';' from dual;
    spool off;
    exit;
ENDSQL

   echo "drop user ${schemaName} cascade;" >> $createUser
   cat ${getUserDDL} >> $createUser
   echo "grant CONNECT to ${schemaName};" >> $createUser
   echo "grant RESOURCE to ${schemaName};" >> $createUser
   fi

   echo "EXIT;" >> $createUser

   # drop and re-create schema(s)
   sqlplus -S -L / as sysdba @$createUser

  echo "Refreshing data from backup dump: `date`"

   # perform import
   impdp \'/ as sysdba\' schemas=$schemaName directory=$impDir dumpfile=$dmpFile logfile=imp_${ORACLE_SID}_`date +%m%d%y`.log

   # perform grants to developer user
   sqlplus -S -L / as sysdba << ENDSQL
   begin
    for x in (select owner,table_name from dba_tables where owner='${schemaName}')
     loop
      execute immediate 'grant select on '||x.owner||'.'|| x.table_name || ' to ${devUserName}';
     end loop;
    end;
   /
ENDSQL

   # retain space
   rm -fr $impPath/$dmpFile
   rm -fr $impPath/${dmpFile}.gz

  #fi

  echo "Finishing dailyRefresh: `date`"
else
 echo "File does not exist at source" | mailx -s "${failMessage}" ${emails}
fi
