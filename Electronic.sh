#!/usr/bin/env bash

function argparse {
    while getopts ":d:mf" opt; do
        case $opt in
        d)
            subdir_name=$OPTARG
            ;;
        m)
            is_submit=true
            ;;
        f)
            is_override=true
            test_tag='-f'
            ;;
        n)
            nband=$OPTARG
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            exit 1
            ;;
        :)
            echo "Option -$OPTARG requires an argument." >&2
            exit 1
            ;;
      esac
    done
}

function subdirectory_check {
    if [[ -d "$subdir_name" && $(ls -A "$subdir_name") ]]; then
        echo -n "Subdirectory contains files. "
        if [[ $is_override ]]; then
            echo "Overriding..."
        else
            echo "Escaping..."
            exit 1
        fi
    fi
}


directory_name=electronic
if [[ "$1" == */ ]]; then subdir_name=${1%/}; else subdir_name=$1; fi
test_type="${subdir_name%%_*}"
test_type2=$2
shift 1

if [[ -d "$directory_name" ]]; then
    cd "$directory_name"
elif [[ "${PWD##*/}" == "$directory_name" ]]; then
    echo "Already in $directory_name/."
else
    echo "The directory $directory_name does not exist!"
    exit 1
fi

if [[ "$test_type" == scrun ]]; then
    subdirectory_check
    argparse "$@"
    cp -r ../INPUT .
#    sed -i "/PREC/c PREC = Accurate" INPUT/INCAR
#    sed -i "/NSW/c NSW = 0" INPUT/INCAR
    sed -i "/LCHARG/c LCHARG = .TRUE." INPUT/INCAR
    sed -i "/LMAXMIX/c LMAXMIX = 4" INPUT/INCAR

    sed -i "/NPAR/c NPAR = 8"  INPUT/INCAR
    sed -i "/#PBS -l walltime/c #PBS -l walltime=03:00:00" INPUT/qsub.parallel
    sed -i "/#PBS -l nodes/c #PBS -l nodes=1:ppn=8" INPUT/qsub.parallel
    Prepare.sh "$subdir_name" $test_tag
    cd scrun
    [[ $is_submit ]] && qsub qsub.parallel

elif [[ "$test_type" == dosrun ]]; then
    subdirectory_check
    argparse "$@"
    Prepare.sh "$subdir_name" $test_tag
    cd dosrun
    cp ../scrun/CONTCAR POSCAR
    cp -l ../scrun/CHGCAR .
    sed -i '4c 21 21 21' KPOINTS

    sed -i "/NSW/c NSW = 0" INCAR
    sed -i "/ISMEAR/c ISMEAR = -5" INCAR
    sed -i "/NEDOS/c NEDOS = 1501" INCAR
    sed -i "/ICHARG/c ICHARG = 11" INCAR
    if [[ $2 == rwigs ]]; then
        rwigs=$(cd ../scrun; CellInfo.sh rwigs |awk '{print $4}')
        sed -i "/RWIGS/c RWIGS = ${rwigs//,/ }" INCAR
        sed -i "/NPAR/c NPAR = 1" INCAR
        sed -i "/LORBIT/c LORBIT = 0"  INCAR
    else
        sed -i "/NPAR/c NPAR = 8"  INCAR
        sed -i "/LORBIT/c LORBIT = 10"  INCAR
    fi

    sed -i "/#PBS -l walltime/c #PBS -l walltime=04:00:00" qsub.parallel
    sed -i "/#PBS -l nodes/c #PBS -l nodes=2:ppn=8" qsub.parallel
    [[ $is_submit ]] && qsub qsub.parallel

elif [[ "$test_type" == bsrun ]]; then
    subdirectory_check
    argparse "$@"
    Prepare.sh "$subdir_name" $test_tag
    cd bsrun
    cp ../scrun/CONTCAR POSCAR
    cp -l ../scrun/CHGCAR .

    if [[ -f KPOINTS-bs ]]; then
        mv KPOINTS-bs KPOINTS
    else
        echo "You must manually change the KPOINTS file before submitting job!"
        exit 1
    fi

    sed -i "/NSW/c NSW = 0" INCAR
    sed -i "/NEDOS/c NEDOS = 1501" INCAR
    sed -i "/ICHARG/c ICHARG = 11" INCAR
    sed -i "/LORBIT/c LORBIT = 10" INCAR

    sed -i "/NPAR/c NPAR = 8"  INCAR
    sed -i "/#PBS -l walltime/c #PBS -l walltime=04:00:00" qsub.parallel
    sed -i "/#PBS -l nodes/c #PBS -l nodes=2:ppn=8" qsub.parallel
    [[ $is_submit ]] && qsub qsub.parallel

elif [[ "$test_type" == lobster && "$test_type2" == kp ]]; then
    subdirectory_check
    shift 1
    argparse "$@"
    Prepare.sh "$subdir_name"-kp $test_tag -a qlobster.kp.serial
    cd "$subdir_name"-kp
    cp ../scrun/CONTCAR POSCAR
    sed -i '4c 17 17 17' KPOINTS

    sed -i "/NSW/c NSW = 0" INCAR
    sed -i "/ISYM/c ISYM = 0" INCAR
    sed -i "/LSORBIT/c LSORBIT = .TRUE." INCAR
    sed -i "/ISMEAR/c ISMEAR = -5" INCAR
    [[ $is_submit ]] && qsub qlobster.kp.serial

elif [[ "$test_type" == lobster && "$test_type2" == test ]]; then
    subdirectory_check
    shift 1
    argparse "$@"
    if [[ -z "$nband" ]]; then
        echo "You must provide NBAND value for the lobster test by -n!"
        exit 1
    fi

    Prepare.sh "$subdir_name" $test_tag -a qlobster.parallel
    cd "$subdir_name"
    if [[ -d ../lobster-kp ]]; then
        echo "Found lobster-kp under electronic/. Moving to this directory for clarity..."
        mv ../lobster-kp .
        cp lobster-kp/IBZKPT KPOINTS
    elif [[ -d lobster-kp ]]; then
        echo "Found lobster-kp under this directory. Good."
        cp lobster-kp/IBZKPT KPOINTS
    else
        echo "Didn't find lobster-kp or full IBZKPT. Did you have your own copied here?"
    fi

    if [[ -f ../scrun/CHGCAR ]]; then
        echo "Use the CHGCAR from the scrun."
        cp ../scrun/CONTCAR POSCAR
        cp -l ../scrun/CHGCAR .
        sed -i "/ICHARG/c ICHARG = 11" INCAR
    fi

    sed -i "/NBANDS/c NBANDS = $nband" INCAR
    sed -i "/NSW/c NSW = 0" INCAR
    sed -i "/ISMEAR/c ISMEAR = -5" INCAR
    sed -i "/NEDOS/c NEDOS = 1501" INCAR
    sed -i "/LORBIT/c LORBIT = 10"  INCAR
    sed -i "/LWAVE/c LWAVE = .TRUE." INCAR

    sed -i "/NPAR/c NPAR = 8"  INCAR
    sed -i "/#PBS -l walltime/c #PBS -l walltime=05:00:00" qsub.parallel
    sed -i "/#PBS -l nodes/c #PBS -l nodes=2:ppn=8" qsub.parallel
    [[ $is_submit ]] && qsub qsub.parallel

elif [[ "$test_type" == lobster && "$test_type2" == analysis ]]; then
    shift 1
    argparse "$@"
    if [[ -d "$subdir_name" && $(ls -A "$subdir_name") ]]; then
        cd "$subdir_name"
    else
        echo "The directory $subdir_name does not exist!"
        exit 1
    fi
    [[ $is_submit ]] && qsub qlobster.parallel

else
    echo "Specify what you are going to test!" >&2
    exit 1
fi
