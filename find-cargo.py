#!/usr/bin/env python3
import os
import sys

def find_top_cargo_tomls(root_dir):
    """
    Finds the shallowest Cargo.toml in every branch and skips subdirectories.
    """
    for root, dirs, files in os.walk(root_dir):
        if 'Cargo.toml' in files:
            # Found one! Print the full path
            print(os.path.join(root, 'Cargo.toml'))
            
            # CRITICAL: Clearing 'dirs' in-place tells os.walk 
            # NOT to look into subdirectories of this folder.
            dirs[:] = []

if __name__ == "__main__":
    # Get root from args or default to Current Working Directory
    target_dir = sys.argv[1] if len(sys.argv) > 1 else "."
    
    if not os.path.isdir(target_dir):
        print(f"Error: '{target_dir}' is not a valid directory.")
        sys.exit(1)
        
    find_top_cargo_tomls(target_dir)
