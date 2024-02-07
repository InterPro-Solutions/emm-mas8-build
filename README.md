# EMM on OpenShift Liberty Installation Guide
This guide will install EZMaxMobile into an OpenShift Cluster via the OpenShift CLI.

Unless otherwise specified, any commands here should be run in a Bash terminal.
## (Windows) Install Git Bash
A bash environment is required to run the installation script. On Windows, this can be installed via [Git Bash](https://git-scm.com/downloads).
## OpenShift CLI
To run the script, the OpenShift CLI executable must be used, found [here](https://docs.openshift.com/container-platform/4.12/cli_reference/openshift_cli/getting-started-cli.html).

You must have an active RedHat subscription to download the OC binary.

You may have to place the OC binary on your `PATH`:
```bash
export PATH=$PATH:<path to OC binary>
```
## Download script
Download or use the included [EMM installation script](emm_install.sh).

You may need to mark the script as executable, i.e by running:
```bash
chmod +x emm_install.sh
```

## Customize environment
If not provided with an `emm*.env` configuration file, you can customize the template [emm.env](emm.env). Example:

```bash
# Core & Manage namespaces to deploy into
# -core is needed for OIDC registration
# -manage is the namespace/project EMM will deploy into
core_namespace=<YOUR OCP MAS CORE NAMESPACE HERE>
manage_namespace=<YOUR OCP MAS MANAGE NAMESPACE HERE>
# Names for EAR & Liberty builds/deployments
# DEFAULT_EMM_EAR is the name of the EAR build config/ImageStream
# DEFAULT_LIBERTY_EAR will affect the final route EMM can be reached on!
DEFAULT_EMM_EAR=emm-ear
DEFAULT_LIBERTY_EAR=emm-liberty
# Deployment info
deploy_package=ezmaxmobile_*.zip
```
## Installation
1. Log in to the OpenShift web console (typically `kubeadmin` username`)
2. In the upper right, click `<username> -> Copy Login Command`
3. Click `Display Token`.
4. Paste the `oc login` command into a terminal.
5. Navigate to the directory of the script (i.e via `cd`) and run:
```bash
./emm_install.sh
```
The initial rollout may take 20-30 minutes to complete.

You may be prompted for the names to use for the deployment and EAR build objects, as well as missing Secrets/ConfigMaps.

For the latter, i.e if the script asks you for `Missing coreidp-binding Secret`, you may have to navigate to `Workloads -> Secrets`,
and search through the `-manage` namespace for an object with a similar name to `coreidp-binding`.

You may also customize an `emm*.env` file, which contains configuration for a specific environment.

4. In the OpenShift web console, navigate to `Networking -> Routes`, and click the Location of the route matching the new deployment.
5. Add `/ezmaxmobile` to your browser's path, and confirm that you are redirected through the MAS 8 authentication flow to EZMaxMobile.

## Redeployment
To rebuild and redeploy EMM, follow these steps:
1. Ensure that the `ezmaxmobile.zip` file has been updated with your changes, wherever it is located.
2. In the OpenShift web console, navigate to `Builds -> BuildConfigs`.
3. Find the row titled `emm-ear-build-config` or similar, select the right three vertical dots menu, then click `Start build`.
4. After the EAR build finishes, monitor the progress of the `emm-liberty-build` (it will start automatically) from `Builds -> Builds`.
5. Once the `emm-liberty-build` has completed, navigate to `Workloads -> Deployments`.
6. Click the `emm-liberty` deployment or similar.
7. Confirm that the deployment has started new pods.
8. Proceed to step `4` of the `Installation` to verify your changes. Note that the application may take about 5 minutes to start up.

If your environment does not include an `-all` server bundle, there will be an additional BuildConfig, `emm-ear-rebuild-config` or similar. This BuildConfig can be run instead in step 3 in the event that only EMM has to rebuilt and Manage has not changed.