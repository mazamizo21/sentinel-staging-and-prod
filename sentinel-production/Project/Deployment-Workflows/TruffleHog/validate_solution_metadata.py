import json
import os
import sys

def validate_metadata(file_path):
    print(f"Validating {file_path}...")
    if not os.path.exists(file_path):
        print(f"Error: File not found: {file_path}")
        return False

    try:
        with open(file_path, 'r') as f:
            data = json.load(f)
    except json.JSONDecodeError as e:
        print(f"Error: Invalid JSON: {e}")
        return False

    resources = data.get('resources', [])
    content_packages = [r for r in resources if r.get('type') == 'Microsoft.OperationalInsights/workspaces/providers/contentPackages']

    if not content_packages:
        print("Error: No 'Microsoft.OperationalInsights/workspaces/providers/contentPackages' resource found.")
        print("This resource is required to define Solution Metadata (Categories, Domains, etc.).")
        return False

    for cp in content_packages:
        props = cp.get('properties', {})
        categories = props.get('categories', {})
        domains = categories.get('domains', [])
        
        print(f"Found Content Package: {cp.get('name')}")
        print(f"Categories: {categories}")
        
        if not domains:
            print("Error: 'domains' list is empty or missing in 'categories'.")
            return False
        
        print("Metadata check PASSED.")
        return True

    return False

if __name__ == "__main__":
    # Check the solution that exists in the workspace
    solution_path = "Solutions/Tacitred-CCF-Hub-v2ThreatIntelligence/Package/mainTemplate.json"
    if validate_metadata(solution_path):
        print("\nSUCCESS: Solution metadata is present and appears valid.")
        sys.exit(0)
    else:
        print("\nFAILURE: Solution metadata is missing or invalid.")
        sys.exit(1)
