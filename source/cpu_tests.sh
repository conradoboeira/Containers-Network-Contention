#!/bin/bash

cpu_cores=$1
networks=("bridge_net" "ovs-br1" "macvlan_net")
#modes=("tcp" "udp" "fct")
modes=("tcp")
#modes=("tcp")
pairs=50
iterations=10

mkdir ./full_results_cpus


#for((i=1;i<=$iterations;i++))
#do
#    for net in "${networks[@]}"
#    do
#        echo "TESTS WITH:" $net
#        mkdir ./full_results_cpus/$net
#        echo "Iteration:" $i
#        mkdir ./full_results_cpus/$net/iteration$i
#        for m in "${modes[@]}"
#        do
#            mkdir ./full_results_cpus/$net/iteration$i
#            bash create-test-base.sh pairs $net $m
#            mv ./results_"$p"_"$net"_fct ./full_results_zeros/$net/iteration$i/
#        done
#    done
#done



for net in "${networks[@]}"
do
    echo "TESTS WITH:" $net
    mkdir ./full_results_cpus/$cpu_cores
    mkdir ./full_results_cpus/$cpu_cores/$net
    for mode in "${modes[@]}"
    do
        echo "Protocol:" $mode
        mkdir ./full_results_cpus/$cpu_cores/$net/$mode
        for((i=1;i<=$iterations;i++))
        do
            bash create-test-base.sh $pairs $net $mode
            mv ./results_"$pairs"_"$net"_"$mode" ./full_results_cpus/$cpu_cores/$net/$mode/iteration$i
        done
    done

    sudo systemctl restart docker

    if [ "$NETWORK" = "ovs-br1" ]; then
        sudo ovs-vsctl del-br ovs-br1
    elif [ "$NETWORK" = "macvlan_net" ]; then
        sudo docker network rm macvlan_net
    elif [ "$NETWORK" = "bridge_net" ]; then
        sudo docker network rm bridge_net
    fi
done
