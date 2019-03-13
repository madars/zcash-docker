# Zcash node in a gVisor-sandboxed Docker container

This repository contains instructions on how to set up a [Zcash](https://z.cash) node in a Docker container, employing Google's [gVisor](https://github.com/google/gvisor) sandbox.

These notes are written relative to a Docker as packaged in Ubuntu 19.04 (disco) but should be easily portable to other Linux distributions as well. The best gVisor sandboxing relies on KVM (available in recent AMD/Intel CPUs), but there is also a (slower and not as thoroughly isolated) ptrace-based sandbox.

## Installing Docker and gVisor

First, install Docker, download a pre-built gVisor binary and place it in `/usr/local/bin`:

```
sudo apt install docker.io

wget https://storage.googleapis.com/gvisor/releases/nightly/latest/runsc
wget https://storage.googleapis.com/gvisor/releases/nightly/latest/runsc.sha512
sha512sum -c runsc.sha512
# outputs "runsc: OK"
chmod a+x runsc
sudo mv runsc /usr/local/bin
```

gVisor is still in development and nightly versions sometimes contain regressions; you can download specific versions by replacing `latest` above with a specific `yyyy-mm-dd` date.

Next, add `runsc` runtime to your Docker configuration (see gVisor's [README](https://github.com/google/gvisor/blob/master/README.md) for more details). As I started with default Docker configuration, it amounted to creating `/etc/docker/daemon.json` with the following contents:

```
{
    "default-runtime": "runsc",
    "runtimes": {
        "runsc": {
            "path": "/usr/local/bin/runsc",
            "runtimeArgs": [
                "--platform=kvm"
            ]
       }
    }
}
```

The only way to instruct Docker to use gVisor in `docker build` process, is to have the `runsc` runtime be the default runtime (e.g., as in the config above). If this is not desired, you should remove the `"default-runtime": "runsc"` line. With `runsc` as the default runtime the `--runtime=runsc` option in the `docker run` commands is superfluous but you might want to keep it to avoid running without `runsc` by accident (for example, in case you change `dockerd` config for some reason).

Finally, restart Docker daemon so that your changes take effect: `sudo systemctl restart docker`.

You might also want to add your own user to the `docker` group (`sudo usermod -a -G docker $USER`) and either relogin or execute the following commands within `su $USER` to make sure that your supplementary groups are updated (and `docker` appears in the output of `id`).

Test that gVisor is working by trying to launch a container:

```
docker run --runtime=runsc -it --rm hello-world
```

## Building and running Zcash

1. First, clone this repository:

```
git clone https://github.com/madars/zcash-docker.git
```

2. Then instruct Docker to build Zcash software and a container for running a Zcash node. On my machine the build process took about 30 minutes, so now is a good time to grab a lunch!

```
docker build --tag=my-zcash-node zcash-docker
```

You can choose the tag freely; similar for the directories in the next step. 

3. Create local directories for storing persistent data, i.e., the Zcash blockchain and the Zcash system parameters:

```
mkdir dot-zcash zcash-params
```

(Tip: when running mainnet and testnet nodes you can share the `zcash-params` volume between the two, and save ~1.6 GB of disk space.)

4. Launch the Zcash node container we just built:

```
docker run --runtime=runsc -it --rm \
    -v $PWD/zcash-params:/home/user/.zcash-params \
    -v $PWD/dot-zcash:/home/user/.zcash \
    my-zcash-node:latest /bin/bash
```

Adding `--rm` makes container be deleted upon exit; that's safe for us as all state lives in the volumes we attach.

5. Finally, run `zcash-fetch-params`, create `.zcash/zcash.conf` (if you are satisfied with defaults, an empty one works!), and launch `zcashd` :-)

## Remarks

- We currently build the most recent git master version of Zcash. If you want a particular release version, you should specify that version in the Dockerfile by editing (`ENV ZCASH_VERSION=...` line).

- We build or containers using [Alpine Linux](https://alpinelinux.org/) as a base. Instead of more commonly used `glibc`, Alpine uses `musl` libc which emphasizes POSIX compatibility. Such libc diversity helps with software quality. Unfortunately, mainline `rust`/`cargo` (including `rustup`-downloaded nightlies, as of mid-January 2019) are incompatible with `musl` libc. Therefore, at least for now, our images are build from `alpine:edge` base and its packaging of Rust. Hopefully in the future we can target a release version of Alpine.

- The only patch we apply to Zcash adds `--with-pic` to `libgmp` Makefile. Without this you get ``libgmp.a(dive_1.o): warning: relocation against `__gmp_binvert_limb_table' in read-only section `.text'`` during linking. We should consult with Zcash upstream about this.

- The node container includes man pages and bash completions for Zcash software (you can run `. /etc/profile` to enable these in bash; Alpine does not provide a `~/.profile` skeleton.)

- The final node image weighs about 540MB, whereas the peak builder image uses about 4.8 GB of space. The latter can be safely deleted, e.g. by a `docker images -f "dangling=true" -q` + `docker rmi` combo.

- This is the first `Dockerfile` I have written so I'm probably not doing things "the Docker way". Patches and comments welcome!
