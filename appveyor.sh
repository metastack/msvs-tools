#!/usr/bin/env bash
# ################################################################################################ #
# MetaStack Solutions Ltd.                                                                         #
# ################################################################################################ #
# AppVeyor CI Configuration                                                                        #
# ################################################################################################ #
# Copyright (c) 2020 MetaStack Solutions Ltd.                                                      #
# ################################################################################################ #
# Author: David Allsopp                                                                            #
# 25-Jun-2020                                                                                      #
# ################################################################################################ #
# Redistribution and use in source and binary forms, with or without modification, are permitted   #
# provided that the following two conditions are met:                                              #
#     1. Redistributions of source code must retain the above copyright notice, this list of       #
#        conditions and the following disclaimer.                                                  #
#     2. Neither the name of MetaStack Solutions Ltd. nor the names of its contributors may be     #
#        used to endorse or promote products derived from this software without specific prior     #
#        written permission.                                                                       #
#                                                                                                  #
# This software is provided by the Copyright Holder 'as is' and any express or implied warranties  #
# including, but not limited to, the implied warranties of merchantability and fitness for a       #
# particular purpose are disclaimed. In no event shall the Copyright Holder be liable for any      #
# direct, indirect, incidental, special, exemplary, or consequential damages (including, but not   #
# limited to, procurement of substitute goods or services; loss of use, data, or profits; or       #
# business interruption) however caused and on any theory of liability, whether in contract,       #
# strict liability, or tort (including negligence or otherwise) arising in any way out of the use  #
# of this software, even if advised of the possibility of such damage.                             #
# ################################################################################################ #

set -e

test ()
{
  echo
  echo -e "\033[33m** \033[32m$1\033[0m"
}

if [[ $1 = 'env' ]] ; then
  echo -e '\033[33mRe-running tests with an environment compiler already set\033[0m'
  TEST_MSVS_PROMOTE_PATH=1
else
  TEST_MSVS_PROMOTE_PATH=0
fi

WHICH=$(which which)

test 'Test msvs-detect --all'
./msvs-detect --all

test 'Ensure msvs-detect locates a compiler'
if "$WHICH" cl &> /dev/null ; then
  cl &> env-cl || true
fi
eval $(./msvs-detect)
echo -e "MSVS_PATH = \033[30m$MSVS_PATH\033[0m"
echo -e "MSVS_INC = \033[30m$MSVS_INC\033[0m"
echo -e "MSVS_LIB = \033[30m$MSVS_LIB\033[0m"
if ! PATH="$MSVS_PATH:$PATH" "$WHICH" cl ; then
  exit 1
else
  if [[ -e detected-cl ]] ; then
    mv detected-cl first-cl
  fi
  PATH="$MSVS_PATH:$PATH" cl &> detected-cl || true
fi
cat detected-cl
if [[ -e env-cl ]] ; then
  test 'Ensure msvs-detect prefers the environment compiler'
  diff env-cl detected-cl
  diff -q first-cl detected-cl &> /dev/null && exit 1
fi

if [[ $TEST_MSVS_PROMOTE_PATH -eq 1 ]] ; then
  test 'Test msvs-promote-path'
  echo "link is currently: $("$WHICH" link)"
  eval $(./msvs-promote-path)
  echo "link is now: $("$WHICH" link)"
  if link --version &> /dev/null ; then
    exit 1
  fi
fi
