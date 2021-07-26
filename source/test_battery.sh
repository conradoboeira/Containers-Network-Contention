#!/bin/bash

networks=("bridge_net" "ovs-br1" "macvlan_net")
modes=("tcp" "fct")
pairs=(1)
iterations=10

mkdir ./full_results_baseline


for((i=4;i<=$iterations;i++))
do
    for net in "${networks[@]}"
    do
        echo "TESTS WITH:" $net
        mkdir ./full_results_baseline/$net
        echo "Iteration:" $i
        mkdir ./full_results_baseline/$net/iteration$i
        for p in "${pairs[@]}"
        do
            bash create-test-base.sh $p $net tcp
            mv ./results_"$p"_"$net"_tcp ./full_results_baseline/$net/iteration$i/
        done
    done
done



#for net in "${networks[@]}"
#do
#    echo "TESTS WITH:" $net
#    mkdir ./full_results/$net
#    for mode in "${modes[@]}"
#    do
#        echo "Protocol:" $mode
#        mkdir ./full_results/$net/$mode
#        for((i=1;i<=$iterations;i++))
#        do
#            echo "Iteration:" $i
#            mkdir ./full_results/$net/$mode/iteration$i
#            for p in "${pairs[@]}"
#            do
#                bash create-test.sh $p $net $mode
#                mv ./results_"$p"_"$net"_"$mode" ./full_results/$net/$mode/iteration$i/
#            done
#        done
#    done
#done
