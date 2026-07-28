#!/usr/bin/env python3
import os
import sys

def parse_tool_versions(filepath):
    tools = {}
    if not os.path.exists(filepath):
        return tools
    with open(filepath, 'r') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            parts = line.split()
            if len(parts) >= 2:
                tools[parts[0]] = parts[1]
    return tools

def generate_a2ml_scm(tools):
    lines = []
    lines.append("(scm-dialect")
    lines.append("  (metadata")
    lines.append("    (schema-version \"1.0\")")
    lines.append("    (generator \"opsm-mise-translator\"))")
    lines.append("  (dependencies")
    
    for tool, version in tools.items():
        lines.append(f"    (package (name \"{tool}\") (version \"{version}\") (provider \"mise\"))")
        
    lines.append("  )")
    lines.append(")")
    return "\n".join(lines)

def main():
    if len(sys.argv) < 3:
        print("Usage: mise_to_a2ml.py <path_to_tool_versions> <output_a2ml_path>")
        sys.exit(1)
        
    input_file = sys.argv[1]
    output_file = sys.argv[2]
    
    tools = parse_tool_versions(input_file)
    if not tools:
        print(f"No tools found or file missing: {input_file}")
        sys.exit(0)
        
    a2ml_content = generate_a2ml_scm(tools)
    
    with open(output_file, 'w') as f:
        f.write(a2ml_content)
        
    print(f"Successfully translated {len(tools)} tools into A2ML SCM dialect at {output_file}")

if __name__ == "__main__":
    main()
