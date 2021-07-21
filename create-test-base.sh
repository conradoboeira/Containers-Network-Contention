#!/bin/sh

PAIRS=$1
NETWORK=$2
MODE=$3
LAG_TIME=2 # 1 for trying stuff 2 for real testing
TEST_TIME=60

#Deploy all necessary containers
echo 'DEPLOYING CONTAINERS'

if [ "$NETWORK" = "ovs-br1" ]; then
	sudo ovs-vsctl add-br ovs-br1
	sudo ifconfig ovs-br1 10.11.0.1 netmask 255.255.0.0 up
	for((t=1;t<=$PAIRS;t++))
	do
		ip=$(( $t+1 ))
        if [ "$MODE" = "fct" ]; then
            sudo docker run -td --entrypoint /bin/sh --name server$t --net=none k/ubuntu-nc > /dev/null
            sudo docker run -td --entrypoint /bin/sh --name client$t --net=none k/ubuntu-nc > /dev/null
        else
            sudo docker run -td --entrypoint /bin/sh --name server$t --net=none k/net-multitool-iperf > /dev/null
            sudo docker run -td --entrypoint /bin/sh --name client$t --net=none k/net-multitool-iperf > /dev/null
        fi
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
        if [ "$MODE" = "fct" ]; then
            sudo docker run -td --entrypoint /bin/sh --name server$t --network $NETWORK --ip 10.11.0.$ip k/ubuntu-nc > /dev/null
            sudo docker run -td --entrypoint /bin/sh --name client$t --network $NETWORK --ip 10.11.1.$ip k/ubuntu-nc > /dev/null
        else
            sudo docker run -td --entrypoint /bin/sh --name server$t --network $NETWORK --ip 10.11.0.$ip k/net-multitool-iperf > /dev/null
            sudo docker run -td --entrypoint /bin/sh --name client$t --network $NETWORK --ip 10.11.1.$ip k/net-multitool-iperf > /dev/null
        fi
		echo 'Deployed pair' $t
	done
fi

echo 'Deployed all containers'
sleep 20s

# Create results directory
RESULTS_DIR=results_"$PAIRS"_"$NETWORK"_"$MODE"
if [ -d "$RESULTS_DIR" ]; then rm -Rf $RESULTS_DIR; fi
mkdir $RESULTS_DIR

#Run the servers and schedule the clients
echo 'SCHEDULING TESTS'

SCHED_TIME=$(date +"%H:%M" -d "$LAG_TIME"min)
echo $SCHED_TIME

for((t=1;t<=$PAIRS;t++))
do
	ip=$(( $t+1 ))
	if [ "$MODE" = "tcp" ]; then
		sudo docker exec -i server$t sh -c 'iperf -s' > /dev/null &
		sudo docker exec -i client$t sh -c 'atd; echo "iperf -c 10.11.0.'"$ip"' -f g -t'"$TEST_TIME"'> out.txt" | at '"$SCHED_TIME"''
	elif [ "$MODE" = "udp" ]; then
		sudo docker exec -i server$t sh -c 'iperf -s -u' > /dev/null &
		sudo docker exec -i client$t sh -c 'atd; echo "iperf -c 10.11.0.'"$ip"' -u -b 75g -f g -t '"$TEST_TIME"' > out.txt" | at '"$SCHED_TIME"''
	elif [ "$MODE" = "fct" ]; then
		sudo docker exec -i server$t sh -c 'nc -l 4444 -d > /dev/null' > /dev/null &
		#sudo docker exec -i server$t sh -c 'iperf -s' > /dev/null &
        sudo docker exec -i client$t sh -c 'atd; echo " (dd if=/dev/zero bs=10000 count=500 | nc -q 1 10.11.0.'"$ip"' 4444 ) > out.txt 2>&1" | at '"$SCHED_TIME"''
		#sudo docker exec -i client$t sh -c 'atd; echo "iperf -c 10.11.0.'"$ip"' -f g -n 5M > out.txt" | at '"$SCHED_TIME"''

	fi
done

echo 'RUNNING TESTS'
# Wait for tests to start
sleep $(( $LAG_TIME ))m

sleep $(( 3 ))m

echo 'SAVING RESULTS'

#Capture all the data

for((t=1;t<=$PAIRS;t++))
do
    #sudo docker exec client$t sh -c "netstat -s > net.txt"
    if [ "$MODE" = "fct" ]; then
        sudo docker cp client$t:/root/out.txt ./$RESULTS_DIR/client"$t"_latency.txt
        #sudo docker cp client$t:/root/net.txt ./$RESULTS_DIR/client"$t"_netstat.txt
    else
        sudo docker cp client$t:/out.txt ./$RESULTS_DIR/client"$t"_latency.txt
        #sudo docker cp client$t:/net.txt ./$RESULTS_DIR/client"$t"_netstat.txt
    fi
done

echo 'SAVED ALL FILES AT' $RESULTS_DIR

#Parse results

if [ "$MODE" = "tcp" ]; then
	sum_transfer=0
	sum_bandwidth=0
	quant=0
	for file in $RESULTS_DIR/*latency.txt;
	do
		transfer=$(awk 'NR==7 {print $5}' $file)
		bandwidth=$(awk 'NR==7 {print $7}' $file)
		sum_transfer=$(echo "scale=3; $sum_transfer + $transfer" | bc)
		sum_bandwidth=$(echo "scale=3; $sum_bandwidth + $bandwidth" | bc)
		quant=$(( $quant + 1 ))
	done

	avg_transfer=$( echo "scale=3; $sum_transfer/$quant" | bc )
	avg_bandwidth=$( echo "scale=3; $sum_bandwidth/$quant" | bc )

	echo "Number of Server/Client Pairs: " $PAIRS >> $RESULTS_DIR/metrics_reports.txt
	echo "Network Interface: " $NETWORK >> $RESULTS_DIR/metrics_reports.txt
	echo "Average Transfer: $avg_transfer" >> $RESULTS_DIR/metrics_reports.txt
	echo "Average Bandwidth: $avg_bandwidth" >> $RESULTS_DIR/metrics_reports.txt

elif [ "$MODE" = "udp" ]; then

    sum_bandwidth=0
    sum_jitter=0
    sum_lost=0
    sum_total=0
    quant=0
    for file in $RESULTS_DIR/*latency.txt;
    do
        bandwidth=$(awk 'NR==12 {print $7}' $file)
        jitter=$(awk 'NR==12 {print $9}' $file)
        lt=$(awk 'NR==12 {print $11}' $file)
        arrlt=(${lt//// })
        sum_bandwidth=$(echo "scale=3; $sum_bandwidth + $bandwidth" | bc)
        sum_jitter=$(echo "scale=3; $sum_jitter + $jitter" | bc)
        sum_lost=$(echo "scale=3; $sum_lost + ${arrlt[0]}" | bc)
        sum_total=$(echo "scale=3; $sum_total + ${arrlt[1]}" | bc)
        quant=$(( $quant + 1 ))
    done

    avg_bandwidth=$( echo "scale=3; $sum_bandwidth/$quant" | bc )
    avg_jitter=$( echo "scale=3; $sum_jitter/$quant" | bc )
    avg_lost=$( echo "scale=3; $sum_lost/$sum_total" | bc )
    echo "Number of Server/Client Pairs: " $PAIRS >> $RESULTS_DIR/metrics_reports.txt
    echo "Average Bandwidth: $avg_bandwidth" >> $RESULTS_DIR/metrics_reports.txt
    echo "Average Jitter: $avg_jitter" >> $RESULTS_DIR/metrics_reports.txt
    echo "Average Lost: $avg_lost" >> $RESULTS_DIR/metrics_reports.txt

elif [ "$MODE" = "fct" ]; then
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
fi

echo "Generated average values at $RESULTS_DIR/metrics_reports.txt"

#Clean up
echo 'CLEANING UP'

seq 1 $PAIRS | parallel sudo docker container stop server{} > /dev/null
seq 1 $PAIRS | parallel sudo docker container rm server{} > /dev/null
seq 1 $PAIRS | parallel sudo docker container stop client{} > /dev/null
seq 1 $PAIRS | parallel sudo docker container rm client{} > /dev/null

sleep 20s

if [ "$NETWORK" = "ovs-br1" ]; then
	sudo ovs-vsctl del-br ovs-br1
elif [ "$NETWORK" = "macvlan_net" ]; then
	sudo docker network rm macvlan_net
elif [ "$NETWORK" = "bridge_net" ]; then
	sudo docker network rm bridge_net
fi

echo 'TESTS FINISHED'

