#!/bin/bash

check_param()
{
	local casename=$1

	log_cmd cd $BENCHMARK_ROOT/$casename/src/test || die "Can not find $casename/src/test dir"

	if [[ "$test" = "non-pmem" ]]; then
		local tmp_dir=$(mktemp -d)
		echo "NON_PMEM_FS_DIR=$tmp_dir" > testconfig.sh
	elif [[ "$test" = "pmem" ]]; then
		echo "PMEM_FS_DIR=/fs/pmem0" > testconfig.sh
	else
		die "Parameter \"test\" is wrong"
	fi

	[[ -n "$group" ]] || die "Parameter \"group\" is empty"

	testcases=$(ls -d "$group"_* 2>/dev/null)

	[[ -n "$testcases" ]] || testcases=$(ls -d "$group" 2>/dev/null)
	[[ -n "$testcases" ]] || die "Parameter \"group\" is invalid"
}


fixup_valgrind()
{
	# at pack/nvml stage, we install valgrind bianries to /tmp/valgrind_install/usr/local
	# and then pack them to /usr/local. However when those binaries are executed,
	# they will reference to /tmp/valgrind_install/user/local where they are installed
	# so here we create a symbolic link to make valgrind work

	log_cmd mkdir -p /tmp/valgrind_install || die "mkdir -p /tmp/valgrind_install failed"
	log_cmd ln -sf /usr /tmp/valgrind_install/usr || die "link failed"
}

build_env()
{
	local casename=$1

	log_cmd cd $BENCHMARK_ROOT/$casename

	fixup_valgrind

	log_cmd make EXTRA_CFLAGS=-DUSE_VALGRIND || die "make test failed"
	log_cmd make EXTRA_CFLAGS=-DUSE_VALGRIND test || die "make test failed"
}

enable_remote_node()
{
	local casename=$1

	log_cmd cd $BENCHMARK_ROOT/$casename/src/test || die "Can not find $casename/src/test dir"

	# To fix no nodes provide. It takes another machines as remote nodes. We can use 
	# localhost as remote node but need to do some configs as below.
	for n in {0..3}
	do
		log_cmd echo "NODE[$n]=127.0.0.1" >> testconfig.sh
		log_cmd mkdir -p "/remote/dir$n" || die "mkdir -p /remote/dir$n failed"
		log_cmd echo "NODE_WORKING_DIR[$n]=/remote/dir$n" >> testconfig.sh
	done

	# enable ssh localhost without password
	pgrep -l sshd || die "ssh server do not run"

	log_cmd ssh-keygen -t rsa -P '' -f ~/.ssh/id_rsa

	log_cmd cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys

	expect -c "set timeout -1;
        spawn ssh 127.0.0.1 exit;
        expect {
            *(yes/no)* {send -- yes\r;exp_continue;}
        }";
}

run()
{
	local casename=$1
	local user_filter="blk_pool log_pool obj_pool pmempool_rm util_file_create util_file_open"

	log_cmd cd $BENCHMARK_ROOT/$casename/src/test

	# to fix SKIP: C++11 required
	log_cmd export CXX=g++

	while read testcase
	do
		if [ "$LKP_LOCAL_RUN" != "1" ] && echo "$user_filter" | grep -q -w "$testcase"; then
			log_cmd chown lkp:lkp -R $BENCHMARK_ROOT/$casename
			log_cmd chown lkp:lkp -R /tmp
			[ "$test" = "pmem" ] && log_cmd chown lkp:lkp -R /fs/pmem0
			log_cmd su lkp -c "./RUNTESTS $testcase  2>&1"
		else
			log_cmd ./RUNTESTS $testcase  2>&1
		fi  
	done <<< "$testcases"
}