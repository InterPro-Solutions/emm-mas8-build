# EMM on OpenShift Liberty Installation Guide
This guide, and the script that accompanies it, were originally based off of Fan's original installation guide.

This guide will install EZMaxMobile into an OpenShift Cluster via the OpenShift CLI.
## (Windows) Install Git Bash
A bash environment is required to run the installation script. On Windows, this can be installed via [Git Bash](https://git-scm.com/downloads).
## OpenShift CLI
To run the script, the OpenShift CLI executable must be used, found [here](https://docs.openshift.com/container-platform/4.12/cli_reference/openshift_cli/getting-started-cli.html).
## Download script
Download the [EMM installation script](emm_install.sh).

You may need to mark the script as executable, i.e by running:
```bash
chmod +x emm_install.sh
```

from a Bash terminal.
## Installation
1. Log in to the OpenShift web console, and select `<username> -> Copy Login Command` from the top right. Click `Display Token`.
2. Paste the `oc login` command into a Bash terminal.
3. Navigate to the directory of the script (i.e via `cd`) and run:
```bash
./emm_install.sh
```
The initial rollout may take around 20 minutes to complete.

You may be prompted for the names to use for the deployment and EAR build objects, as well as missing Secrets/ConfigMaps.

For the latter, i.e if the script asks you for `Missing coreidp-binding Secret`, you may have to navigate to `Workloads -> Secrets`,
and search through the `-manage` namespace for an object with a similar name to `coreidp-binding`.
4. In the OpenShift web console, navigate to `Networking -> Routes`, and click the Location of the route matching the new deployment.
5. Add `/ezmaxmobile` to your browser's path, and confirm that you are redirected through the MAS 8 authentication flow to EZMaxMobile.
