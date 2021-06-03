-- check mgmtdb status
srvctl status mgmtdb

-- start mgmtdb (let cluster decided node to start on)
srvctl start mgmtdb

-- start mgmtdb on specific node
srvctl start mgmtdb -node <NODE-NAME>

-- start mgmtdb w/ options (example OPEN, MOUNT, or NOMOUNT)
srvctl start mgmtdb --startoption <OPTION>
