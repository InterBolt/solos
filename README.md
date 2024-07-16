# 🔭 SolOS - The Introspective Dev Environment
A Docker-based development environment built for self-analysis.

## Documentation
Documentation in progress at [https://docs.solos.sh](https://docs.solos.sh).

## Overview
SolOS is a MacOS CLI tool that seamlessly orchestrates and manages a long-running development container and centralized master volume on a users' host machine (at `$HOME/.solos`). The master volume is mounted into the active development container and stores all of a user's development-related work (ie. scripts, repositories, experiments, notes, activity data, etc) across a variety of projects. 

> 💡 Customizing the development container is as simple as editing a generated Dockerfile and typing `solos rebuild <project>`

Most importantly, SolOS includes a custom Bash shell with some utility commands and tracking capabilities built-in. Within this shell, a user can install and run various third party plugins (or their own custom plugins) to process their master volume and export the results to external systems, such as an LLM chatbot backend or classic reporting tool.

> 🔒 For the security conscious folks, see the security considerations section below.

## The Vision
The vision of SolOS is to provide a sufficiently delightful way of working so that its users are rarely, if ever, tempted to leave the system. **The more of a developer's activity that is stored inside the master volume (due to them staying within the SolOS system), the more *detailed and holistic* a knowledge base that plugins can create.**

## Installation
Requires: **MacOS**, **Bash** version >= 3, **Git**, **Docker**, **VSCode**

```sh
curl -o install.sh "https://raw.githubusercontent.com/InterBolt/solos/main/install/install.sh?token=$(date +%s)"
chmod +x install.sh
./install.sh
```

### Verify Installation
Run the following command to verify that SolOS has been installed correctly:
```sh
solos --help
```

### Launch a project's shell:
```sh
# Launches the custom SolOS shell
solos bash <project>

# Or opt-out of customizations and load a plain interactive Bash session:
solos bash:minimal <project>
```

### Launch a project in VSCode
> 💡 The SolOS shell is the default integrated terminal for the VSCode workspace.
```sh
solos vscode <project>
```

### Rebuild a project's Docker container:
> 💡 Useful if a user recently modified their project's Dockerfile
```sh
solos rebuild <project>

# Build the container without using Docker's cache
solos rebuild:no-cache <project>
```

### Dispose of the development container
```sh
solos dispose
```

## Plugins
Plugins make it possible to extract interesting information from a user's master volume for third party systems to consume. The best way to understand how a plugin works is to review SolOS's ["precheck" plugin](https://github.com/InterBolt/solos/blob/main/src/daemon/plugins/precheck/plugin). A plugin executable runs in discrete phases, where each phase has access to different files, folders, and network conditions. The precheck plugin linked above validates all access assumptions.

## Security Considerations
User-installed plugins are just executables. SolOS mitigates the risk of running them by:
- Executing them within a private, firejailed sandbox with restricted filesystem and network access.
- Only allowing access to a heavily scrubbed copy of the developer's master volume (`~/.solos`).

The scrubbing mechanism automatically removes high-risk files and secrets, prunes gitignored files, and more. SolOS users are encouraged (but not required) to download executables from trusted sources, such as popular GitHub repositories, which means the above **mitigations are more to prevent accidental, rather than malicious, leakages** of sensitive information.

## Contributor Commandments
- **Guard against corporate spyware use cases**.
- **Minimize configuration requirements.**
- **Ensure seamless migrations between machines**.
- **Ensure the base Docker image remains unopinionated**.
- **Adopt a conservative approach to the shell API**.
- **Make source code easily inspectable and modifiable** without complicated build pipelines or compilation steps.
- **Limit the scope of SolOS** to the following: 1) the plugin daemon, 2) custom shells, 3) IDE integrations, and 4) a host CLI. Prefer internal plugins for other functionalities.