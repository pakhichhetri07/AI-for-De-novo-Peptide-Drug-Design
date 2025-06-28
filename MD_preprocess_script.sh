#!/bin/bash

set -e 

INPUT_DIR="/mnt/c/Users/Admin/Desktop/IIT_R_Docs/PEPTIDE_MODELLING/Simulations/Final/Docked_Structures_Edited/CTXM_1_edited"
OUTPUT_DIR="/mnt/c/Users/Admin/Desktop/IIT_R_Docs/PEPTIDE_MODELLING/Simulations/Final/Simulation_results/CTXM_1_simulation"
MDP_SRC_DIR="/mnt/c/Users/Admin/Desktop/IIT_R_Docs/PEPTIDE_MODELLING/Simulations/Final"  

mkdir -p "$OUTPUT_DIR"

export GMX_PATH="/root/miniconda3/envs/gromacs_env/bin.AVX2_256"
export PATH="$GMX_PATH:$PATH"

MDP_FILES=("ions.mdp" "minim.mdp" "nvt.mdp" "npt.mdp" "md.mdp")

for mdp in "${MDP_FILES[@]}"; do
    if [ ! -f "$MDP_SRC_DIR/$mdp" ]; then
        echo "Error: Missing required file $MDP_SRC_DIR/$mdp"
        exit 1
    fi
done

process_pdb() {
    pdb_file="$1"
    filename=$(basename "$pdb_file" .pdb)
    work_dir="$OUTPUT_DIR/$filename"

    mkdir -p "$work_dir"
    cp "$pdb_file" "$work_dir/$filename.pdb"

    for mdp in "${MDP_FILES[@]}"; do
        cp "$MDP_SRC_DIR/$mdp" "$work_dir/"
    done

    "$GMX_PATH/gmx" pdb2gmx -f "$work_dir/$filename.pdb" -o "$work_dir/fnl_processed.gro" \
        -ff amber99sb-ildn -water tip3p -p "$work_dir/topol.top" -i "$work_dir/posre.itp" <<EOF
6
EOF

    "$GMX_PATH/gmx" editconf -f "$work_dir/fnl_processed.gro" -o "$work_dir/fnl_newbox.pdb" -c -d 1.0 -bt cubic
    "$GMX_PATH/gmx" solvate -cp "$work_dir/fnl_newbox.pdb" -cs spc216.gro -o "$work_dir/fnl_solv.gro" -p "$work_dir/topol.top"
    "$GMX_PATH/gmx" editconf -f "$work_dir/fnl_solv.gro" -o "$work_dir/fnl_solv.pdb"

    "$GMX_PATH/gmx" grompp -f "$work_dir/ions.mdp" -c "$work_dir/fnl_solv.gro" -p "$work_dir/topol.top" -o "$work_dir/ions.tpr" -maxwarn 2

    echo "13" | "$GMX_PATH/gmx" genion -s "$work_dir/ions.tpr" -o "$work_dir/fnl_solv_ions.gro" -pname NA -nname CL -neutral -conc 0.15 -p "$work_dir/topol.top"

    "$GMX_PATH/gmx" grompp -f "$work_dir/minim.mdp" -c "$work_dir/fnl_solv_ions.gro" -p "$work_dir/topol.top" -o "$work_dir/em.tpr"
    "$GMX_PATH/gmx" mdrun -v -deffnm "$work_dir/em"
    "$GMX_PATH/gmx" editconf -f "$work_dir/em.gro" -o "$work_dir/em.pdb"

    "$GMX_PATH/gmx" energy -f "$work_dir/em.edr" -o "$work_dir/pe_em.xvg" <<EOF
10 0
EOF

    "$GMX_PATH/gmx" grompp -f "$work_dir/nvt.mdp" -c "$work_dir/em.gro" -r "$work_dir/em.gro" -p "$work_dir/topol.top" -o "$work_dir/nvt.tpr"
    "$GMX_PATH/gmx" mdrun -nt 8 -deffnm "$work_dir/nvt"

    "$GMX_PATH/gmx" grompp -f "$work_dir/npt.mdp" -c "$work_dir/nvt.gro" -r "$work_dir/nvt.gro" -t "$work_dir/nvt.cpt" -p "$work_dir/topol.top" -o "$work_dir/npt.tpr" -maxwarn 2
    "$GMX_PATH/gmx" mdrun -nt 8 -deffnm "$work_dir/npt"

    "$GMX_PATH/gmx" grompp -f "$work_dir/md.mdp" -c "$work_dir/npt.gro" -t "$work_dir/npt.cpt" -p "$work_dir/topol.top" -o "$work_dir/md_0_1.tpr"

    echo "Simulation completed for $filename"
}

export -f process_pdb

for pdb_file in "$INPUT_DIR"/*.pdb; do
    if [[ -f "$pdb_file" ]]; then
        process_pdb "$pdb_file" || echo "Error processing $pdb_file"
    else
        echo "Skipping invalid file: $pdb_file"
    fi
done

echo "All simulations processed successfully!"