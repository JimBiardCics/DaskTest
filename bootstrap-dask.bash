#!/bin/bash

set -e

# Add a line to the .bashrc to remove the python alias.
#
echo 'unalias python' >> $HOME/.bashrc

# Check if running on the master node. If not, there's nothing do.
#
grep -q '"isMaster": true' /mnt/var/lib/info/instance.json \
|| { echo "Not running on master node, nothing to do" && exit 0; }

# If there is an argument, it is the name of a git repository to pull.
#
if [[ ${#} -eq 1 ]]
then
    repo=${1}
fi

# Install Miniconda
#
echo "Installing Miniconda"

curl -L https://repo.continuum.io/miniconda/Miniconda3-latest-Linux-x86_64.sh -o /tmp/miniconda.sh

bash /tmp/miniconda.sh -b -p $HOME/miniconda

rm /tmp/miniconda.sh

echo -e '\nexport PATH=$HOME/miniconda/bin:$PATH' >> $HOME/.bashrc

source $HOME/.bashrc

conda update conda -y

# Install packages to use in packaged environment
#
echo "Installing base packages"

conda install -c conda-forge -y -q \
git \
dask-yarn \
pyarrow \
s3fs \
conda-pack \
tornado \
numpy \
netCDF4 \
xarray \
bokeh=2.0 \
notebook \
ipywidgets \
jupyter-server-proxy

# Package the environment to be distributed to worker nodes
#
echo "Packaging environment"

conda pack -q -o $HOME/environment.tar.gz

# List all packages in the worker environment
#
echo "Packages installed in the worker environment:"

conda list

# Configure Dask
#
echo "Configuring Dask"

mkdir -p $HOME/.config/dask

cat <<EOT >> $HOME/.config/dask/config.yaml
distributed:
  dashboard:
    link: "/proxy/{port}/status"

yarn:
  environment: /home/hadoop/environment.tar.gz
  deploy-mode: local

  worker:
    env:
      ARROW_LIBHDFS_DIR: /usr/lib/hadoop/lib/native/

  client:
    env:
      ARROW_LIBHDFS_DIR: /usr/lib/hadoop/lib/native/
EOT

# Also set ARROW_LIBHDFS_DIR in ~/.bashrc so it's set for the local user
#
echo -e '\nexport ARROW_LIBHDFS_DIR=/usr/lib/hadoop/lib/native' >> $HOME/.bashrc

# Configure Jupyter Notebook
#
echo "Configuring Jupyter"

mkdir -p $HOME/.jupyter

HASHED_PASSWORD=`python -c "from notebook.auth import passwd; print(passwd('dask-user'))"`

cat <<EOF >> $HOME/.jupyter/jupyter_notebook_config.py
c.NotebookApp.password = u'$HASHED_PASSWORD'
c.NotebookApp.open_browser = False
c.NotebookApp.ip = '0.0.0.0'
EOF

# Do everything else from the home folder.
#
cd $HOME

# If a git repo was specified, load the code.
#
if [[ ${repo} ]]
then
    git clone ${repo}
fi

# Enter the repository top-level folder.
#
topFolder=${repo##*/}
topFolder=${topFolder%.git}

cd ${topFolder}

# Start the Jupyter Notebook Server.
#
echo "Starting Jupyter Notebook Server"

jupyter-notebook > /var/log/jupyter-notebook.log 2>&1 &

disown -h %1

echo "Done."
