# 🔭 SolOS - The Compounding Dev Environment
SolOS is a MacOS CLI tool that seamlessly orchestrates long-running development containers and provides some useful goodies along the way.

## Documentation
Documentation in progress at [https://docs.solos.sh](https://docs.solos.sh).

## Architecture

Consider the following command:

```sh
solos bash myproject
```

When ran this command:

1) Invokes the installed SolOS bin script at `/usr/local/bin/solos` using Bash.
   > This script keeps portability in mind.
2) The bin script initializes the "myproject" docker image, while ensuring no other active project containers are running. 
   > On the first run of this command a default dockerfile specific to "myproject" defines the initial container build. It's customizable later.
3) Next, the bin script invokes a verification command in the newly created project container, preparing any necessary state along with some sanity checks.
4) Once the project container is verfied, our bin script has the confidence to launch a new bash session. The session includes all kinds of useful things as a result of the rcfile it uses. Ie. **tracks all user commands and their stdout/stderr**, **exposes lifecycle hooks for pre/post user command**, **sets up git and github authentication**, **automates pulling in or creating new apps and their repos**, **provides a way to extend command lifecycles and tracking mechanisms**, and more.

## The Vision
Encourage the accrual of organization specific cheat codes to make work simpler and more reproducable. 

For example, maybe your company's dev services go down more often and/or break in non-obvious ways. A developer can add pre and post exec checks in the project's generated rcfile specific to each app. Ie. an "app" that contains some frontend code might ping the backend services it calls before any use of "npm run start" in the projects shell.

And as more and more environment quirks are needed, the project specific dockerfile allows a developer to customize to their hearts delight.

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

## Contributor Commandments
- **Guard against corporate spyware use cases**.
- **Minimize configuration requirements.**
- **Ensure seamless migrations between machines**.