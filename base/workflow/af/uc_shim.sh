# setting up users
if [ "$OWNER" != "" ] && [ "$CONNECT_GROUP" != "" ]; then
    PATH=$PATH:/usr/sbin
    # Set the user's $DATA dir
    export DATA=/data/$OWNER
    if [ -z "$OWNER_UID" ] || [ -z "$CONNECT_GID" ]; then 
        echo "No UID or GID, cowardly aborting"
        exit 1
    else
        # Create the base group
        groupadd "$CONNECT_GROUP" -g "$CONNECT_GID"
        # Create the user with no home directory (should already exist on NFS)
        # and the correct UID/GID
        useradd "$OWNER" -M -u "$OWNER_UID" -g "$CONNECT_GROUP"
    fi  
    # Match PS1 as we have it on the login nodes
    echo 'export PS1="[\A] \H:\w $ "' >> /etc/bash.bashrc
    # Read the user's customization script and install extras
    if [ -f /home/$OWNER/.jupyter/customize ]; then
        echo "Installing customizations for $OWNER"
        pip install -r /home/$OWNER/.jupyter/customize
    fi  
    # Change to the user's homedir
    if [ ! -z "$OWNER" ]; then
        echo "Chowning venv to user"
        chown -R $OWNER: /jupyter
        echo "Chowning workspace dir to user"
        chown -R $OWNER: /workspace
    fi  
    cd /home/$OWNER
    
    # get tutorial in.
    # cp -r /ML_platform_tests/tutorial ~/. 

    # Re-export the token into the user environment
    echo "export JUPYTER_TOKEN=$JUPYTER_TOKEN" >> /etc/profile.d/jupyter.sh
    su - $OWNER -c "jupyter lab --ServerApp.root_dir=/home/${OWNER} --no-browser --config=/usr/local/etc/jupyter_notebook_config.py"
    sleep 600 
fi 