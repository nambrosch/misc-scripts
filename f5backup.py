#!/usr/bin/env python

# https://support.f5.com/csp/article/K8465
# to read encrypted ucs files run gpg <filename.ucs>

# https://devcentral.f5.com/wiki/iControl.System__ConfigSync.ashx
# icontrol system.configsync used to read config

import argparse
import base64
import bigsuds
import getpass
import glob
import os
import socket
import sys
import time

# parse command-line input
parser = argparse.ArgumentParser()
parser.add_argument('hostname', help='hostname of bigip')
parser.add_argument('-a', help='archive type', default='text', choices=('text','ucs'), required=False)
parser.add_argument('-b', help='base directory', default=os.path.dirname(os.path.realpath(sys.argv[0])), required=False)
parser.add_argument('-p', help='bigip password', required=False)
parser.add_argument('-s', help='ucs secret', default='Secret!', required=False)
parser.add_argument('-u', help='bigip username', required=False)
args = parser.parse_args()

# make sure the specified hostnamae resolves (even if it's an ip)
try:
    hostname = args.hostname
    socket.gethostbyname(hostname)
except:
    print 'invalid hostname: ' + hostname
    sys.exit(1)

# don't run if the specified base directory isn't an existing directory
if os.path.isfile(args.b):
    print 'specified base directory is a file!'
    sys.exit(1)

elif not os.path.isdir(args.b):
    print 'base directory does not exist!'
    sys.exit(1)

else:
    # prompt for a username if it wasn't entered
    if args.u:
        username = args.u
    else:
        username = raw_input('Username: ')

    # prompt for a password if it wasn't entered
    if args.p:
        password = args.p
    else:
        password = getpass.getpass()

    # store ucs files beneath the base directory
    basedir = args.b
    ucsdir = basedir + '/' + hostname

    try:
        # create bigsuds connection object
        b = bigsuds.BIGIP(hostname,username,password)

        # timestamp of the running config
        cid = b.Management.DBVariable.query(['Configsync.LocalConfigTime'])[0]['value']

        # make sure we have a place to put the ucs file
        if not os.path.isfile(ucsdir) and not os.path.isdir(ucsdir):
            os.makedirs(ucsdir)

        # tell bigip to create a ucs archive
        filename = 'config_' + cid + '_' + time.strftime('%Y%m%d_%H%M%S') + '.ucs'
        filepath = ucsdir + '/' + filename

        if args.a == 'ucs':
            print 'creating encrypted ucs archive...'
            b.System.ConfigSync.save_encrypted_configuration(filename,args.s)
        else:
            print 'creating ucs archive...'
            b.System.ConfigSync.save_configuration(filename,'SAVE_FULL')

        # download the ucs archive we just created
        print 'downloading ucs archive...'
        f = open(filepath,'wb')

        chunk_size = 65536
        file_offset = 0
        write_continue = 1

        while write_continue == 1:
            # request base64-encoded ucs data starting from this iteration's offset
            temp_config = b.System.ConfigSync.download_configuration(filename,chunk_size,file_offset)
            file_info = temp_config['return']
            f.write(base64.b64decode(file_info['file_data']))

            # detect end of file
            if file_info['chain_type']  == 'FILE_LAST' or file_info['chain_type'] == 'FILE_FIRST_AND_LAST':
                write_continue = 0

            # set offset
            file_offset = file_offset + chunk_size

        # close file and remove ucs file from the bigip
        f.close()
        b.System.ConfigSync.delete_configuration(filename)

        # yoink files we want in a text backup and delete the ucs, otherwise just save the ucs
        if args.a == 'text':
            print 'extracting ucs archive...'

            # create temporary directory and extract ucs
            ucstmp = ucsdir + '/tmp'
            if not os.path.exists(ucstmp):
                os.makedirs(ucstmp)
            os.system('tar --strip-components=1 --overwrite -xf ' + filepath + ' -C ' + ucstmp)

            # move the easy objects first
            os.system('mv -f ' + ucstmp + '/BigDB.dat ' + ucsdir + '/')
            os.system('mv -f ' + ucstmp + '/bigip.conf ' + ucsdir + '/')
            os.system('mv -f ' + ucstmp + '/bigip_base.conf ' + ucsdir + '/')
            os.system('mv -f ' + ucstmp + '/bigip.license ' + ucsdir + '/')
            os.system('mv -f ' + ucstmp + '/bigip_user.conf ' + ucsdir + '/')

            # make a list of filestore objects
            files = sorted(glob.glob(ucstmp + '/tmp/filestore_temp/files_d/Common_d/*/*'))
            dict = {}

            # populate dict with the files and their revisions
            for f in files:
                if os.path.isfile(f) and 'certificate' not in f:
                    file = f.rsplit('_', 2)[0]
                    rev = f.rsplit('_', 2)[1] + '.' + f.rsplit('_', 2)[2]

                    if file not in dict:
                        dict[file] = [rev]
                    else:
                        dict[file] += [rev]

            # determine which revision to move
            for f in dict:
                ucsfilestore = ucsdir + '/' + f.split('/')[-2]
                if not os.path.exists(ucsfilestore):
                    os.makedirs(ucsfilestore)
                os.system('mv -f ' + f + '_' + max(dict[f]).replace('.','_') + ' ' + ucsfilestore + '/' + f.split(':')[-1])

            # remove ucs from disk since we aren't keeping it
            os.system('rm -Rf ' + filepath + ' ' + ucstmp)
        print 'done!'

    except Exception, e:
        print 'something bad happened... exiting.'
        print str(e)
        sys.exit(1)
