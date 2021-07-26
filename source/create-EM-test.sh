#!/bin/sh

PAIRS=$1
NETWORK=$2
LAG_TIME=2 # 1 for trying stuff 2 for real testing
TEST_TIME=60
ELEPHANT_RATIO=5 # Define N where 1 every N flow will be an Elephant flow
ELEPHANT_SIZE=50 # Elephant flow size in MB
MOUSE_SIZE=5 # Elephant flow size in MB

#Deploy all necessary containers
echo 'DEPLOYING CONTAINERS'

if [ "$NETWORK" = "ovs-br1" ]; then
	sudo ovs-vsctl add-br ovs-br1
	sudo ifconfig ovs-br1 10.11.0.1 netmask 255.255.0.0 up
	for((t=1;t<=$PAIRS;t++))
	do
		ip=$(( $t+1 ))
        sudo docker run -td --entrypoint /bin/sh --name server$t --net=none k/ubuntu-nc > /dev/null
        sudo docker run -td --entrypoint /bin/sh --name client$t --net=none k/ubuntu-nc > /dev/null
		sudo ovs-docker add-port ovs-br1 eth0 server$t --ipaddress=10.11.0."$ip"/16 --gateway=10.11.0.1
		sudo ovs-docker add-port ovs-br1 eth0 client$t --ipaddress=10.11.1."$ip"/16 --gateway=10.11.0.1
		echo 'Deployed pair' $t
	done

else
	if [ "$NETWORK" = "macvlan_net" ]; then
		sudo docker network create -d macvlan --subnet=10.11.0.0/16  -o parent=ens160 macvlan_net
	elif [ "$NETWORK" = "bridge_net" ]; then
		sudo docker network create -d bridge --subnet=10.11.0.0/16 bridge_net
	fi
	for((t=1;t<=$PAIRS;t++))
	do
		ip=$(( $t+1 ))
        sudo docker run -td --entrypoint /bin/sh --name server$t --network $NETWORK --ip 10.11.0.$ip k/ubuntu-nc > /dev/null
        sudo docker run -td --entrypoint /bin/sh --name client$t --network $NETWORK --ip 10.11.1.$ip k/ubuntu-nc > /dev/null
		echo 'Deployed pair' $t
	done
fi

echo 'Deployed all containers'
sleep 20s

# Create results directory
RESULTS_DIR=results_"$PAIRS"_"$NETWORK"_EM_test
if [ -d "$RESULTS_DIR" ]; then rm -Rf $RESULTS_DIR; fi
mkdir $RESULTS_DIR

#Run the servers and schedule the clients
echo 'SCHEDULING TESTS'

SCHED_TIME=$(date +"%H:%M" -d "$LAG_TIME"min)

for((t=1;t<=$PAIRS;t++))
do
	ip=$(( $t+1 ))
    sudo docker exec -i server$t sh -c 'nc -l 4444 -d > /dev/null' > /dev/null &
    if (( $t % $ELEPHANT_RATIO == 0 )); then
        sudo docker exec -i client$t sh -c 'atd; echo "(dd if=/dev/zero bs=10000 count='"$ELEPHANT_SIZE"'00 | nc -q 1 10.11.0.'"$ip"' 4444 ) > out.txt 2>&1" | at '"$SCHED_TIME"''
    else
        sudo docker exec -i client$t sh -c 'atd; echo "(dd if=/dev/zero bs=10000 count='"$MOUSE_SIZE"'00 | nc -q 1 10.11.0.'"$ip"' 4444 ) > out.txt 2>&1" | at '"$SCHED_TIME"''
    fi
done

echo 'RUNNING TESTS'
# Wait for tests to start
sleep $(( $LAG_TIME ))m

sleep $(( 2 ))m

echo 'SAVING RESULTS'

#Capture all the data
for((t=1;t<=$PAIRS;t++))
do
    sudo docker cp client$t:/root/out.txt ./$RESULTS_DIR/client"$t"_latency.txt
done

echo 'SAVED ALL FILES AT' $RESULTS_DIR

#Parse results


sum_time=0
quant=0
for file in $RESULTS_DIR/*latency.txt;
do
    time=$(awk 'NR==3 {print $6}' $file)
    sum_time=$(echo "scale=3; $sum_time + $time" | bc)
    quant=$(( $quant + 1 ))
done

avg_time=$( echo "scale=3; $sum_time/$quant" | bc )
echo "Average Time: $avg_time" >> $RESULTS_DIR/metrics_reports.txt

echo "Generated average values at $RESULTS_DIR/metrics_reports.txt"

#Clean up
echo 'CLEANING UP'

seq 1 $PAIRS | parallel sudo docker container stop server{} > /dev/null
seq 1 $PAIRS | parallel sudo docker container rm server{} > /dev/null
seq 1 $PAIRS | parallel sudo docker container stop client{} > /dev/null
seq 1 $PAIRS | parallel sudo docker container rm client{} > /dev/null


if [ "$NETWORK" = "ovs-br1" ]; then
	sudo ovs-vsctl del-br ovs-br1
elif [ "$NETWORK" = "macvlan_net" ]; then
	sudo docker network rm macvlan_net
elif [ "$NETWORK" = "bridge_net" ]; then
	sudo docker network rm bridge_net
fi

echo 'TESTS FINISHED'

