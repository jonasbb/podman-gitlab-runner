# Using Podman to power your Gitlab CI pipeline

1. [Installation and Setup](#installation-and-setup)
    1. [Installing the gitlab-runner](#installing-the-gitlab-runner)
    2. [Setting up a Runner Instance](#setting-up-a-runner-instance)
2. [Tweaking the Installation](#tweaking-the-installation)
3. [License](#license)
4. [Links](#links)

## Installation and Setup

The install instructions are for a Fedora 31+ installation.
Most of the instructions should transfer to other distributions.
gitlab-runner needs to be installed in version 12.6 or higher, because we rely on the `image` tag being exposed from the `.gitlab-ci.yml` file.

### Installing the gitlab-runner

First, you need to install the [gitlab-runner][gitlab-runner-install] using the instructions listed on the website.
You can silence the SELinux warnings, by labelling the binary with the proper `bin_t` type like:

```bash
sudo chcon -t bin_t /usr/bin/gitlab-runner
```

Ensure that the gitlab-runner service runs with the appropirate permissions.
Since we are using Podman in a rootless setup, we can run the service with user privileges instead of root permissions.
Edit the service file (`/etc/systemd/system/gitlab-runner.service`) and add the `User` and `Group` lines in the service section.

```ini
[Service]
User=gitlab-runner
Group=gitlab-runner
```

**Note:** This step has to be re-done on every update of the `gitlab-runner` package, since it overwrites the modifications to the service file. This is because the package places the service file into the wrong directory.

### Setting up a Runner Instance

As the gitlab-runner user change into the home directory (`/home/gitlab-runner`) and clone this repository.

```bash
git clone https://github.com/jonasbb/podman-gitlab-runner
```

Then follow the [instructions][gitlab-runner-register] to set up a new runner instance:

```bash
sudo -u gitlab-runner gitlab-runner register \
    --url https://my.gitlab.instance/ \
    --registration-token $GITLAB_REGISTRATION_TOKEN \
    --name "Podman Runner" \
    --executor custom \
    --builds-dir /home/user \
    --cache-dir /home/user/cache \
    --custom-prepare-exec "/home/gitlab-runner/prepare.sh" \
    --custom-run-exec "/home/gitlab-runner/run.sh" \
    --custom-cleanup-exec "/home/gitlab-runner/cleanup.sh"
```

## Tweaking the Installation

Currently, the scripts do not provide much customization.
However, you can adapt the functions `start_container` and `install_dependencies` to specify how Podman should spawn the containers and how to install the dependencies.

Some behaviour can be tweaked by tweaked by setting the correct environment variables.
Rename the `custom_base.template.sh` file into `custom_base.sh` to make use of the customization.
The following variables are supported right now:

* `PODMAN_RUN_ARGS`: Customize how Podman spawns the containers.

Podman supports access to private Gitlab registries.
You can set the `DOCKER_AUTH_CONFIG` variable under **Settings → CI / CD** and provide the credentials for accessing the private registry.
Details how the variable has to look can be found under [using statically defined credentials][gitlab-static-credentials] in the Gitlab documentation.

## License

Licensed under the [MIT license].

Unless you explicitly state otherwise, any contribution intentionally submitted for inclusion in this project by you, as defined in the Apache-2.0 license, shall be dual licensed as above, without any additional terms or conditions.

## Links

* <https://tech.immerda.ch/2019/10/gitlab-ci-with-podman/>  
    First source describing how to set up Podman and gitlab-runner and the source for these scripts.
* <https://docs.gitlab.com/runner/executors/custom.html>  
    Official documentation about the custom executor feature for Gitlab CI.
* <https://docs.gitlab.com/runner/executors/custom_examples/>  
    Official examples how to use the custom executor feature.

[gitlab-runner-install]: https://docs.gitlab.com/runner/install/linux-repository.html
[gitlab-runner-register]: https://docs.gitlab.com/runner/register/
[gitlab-static-credentials]: https://docs.gitlab.com/ee/ci/docker/using_docker_images.html#using-statically-defined-credentials
[MIT license]: LICENSE
