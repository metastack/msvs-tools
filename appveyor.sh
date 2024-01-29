#!/usr/bin/env bash
# ################################################################################################ #
# MetaStack Solutions Ltd.                                                                         #
# ################################################################################################ #
# AppVeyor CI Configuration                                                                        #
# ################################################################################################ #
# Copyright (c) 2020 MetaStack Solutions Ltd.                                                      #
# Copyright (c) 2024 David Allsopp Ltd.                                                            #
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

set -eo pipefail

test ()
{
  echo
  echo -e "\033[33m** \033[32m$1\033[0m"
}

note ()
{
  echo -e "\033[36m$1\033[0m"
}

declare -A TESTS

gather ()
{
  note "Gathering data from $2 on $3"
  TESTS["$2-$3"]="\"$4\" $5"
  echo -ne '\033[30m'
  ./msvs-detect --arch=$3 --output=data -- $2 | tee "$2-$3.clean"
  echo -ne '\033[0m'
}

display_env ()
{
  echo "MSVS_NAME = $MSVS_NAME"
  echo -ne 'MSVS_PATH = \033[30m'
  echo -n "$MSVS_PATH"
  echo -ne '\033[0m\nMSVS_INC = \033[30m'
  echo -n "$MSVS_INC"
  echo -ne '\033[0m\nMSVS_LIB = \033[30m'
  echo -n "$MSVS_LIB"
  echo -e '\033[0m'
}

matrix ()
{
  while IFS= read -r line; do
    eval "gather $line"
  done < <(grep '^-' all-compilers)
  failed=0
  for key in "${!TESTS[@]}"; do
    echo
    note "Testing with environment set for $key"
    if command -v cl; then
      echo 'cl in path!'>&2
      exit 1
    fi
    if ! SCRIPT="${TESTS[$key]}" cmd /d /v:on /c appveyor.cmd ${key%-*} ${key#*-}; then
      failed=1
    fi
    if command -v cl; then
      echo 'cl in path!'>&2
      exit 1
    fi
  done
  if [[ $failed -eq 1 ]]; then
    exit 1
  fi
}

case "$1" in
  env)
    echo -e '\033[33mRe-running tests with an environment compiler already set\033[0m'
    TEST_ENVIRONMENT=1;;
  *)
  TEST_ENVIRONMENT=0;;
esac

WHICH=$(which which)

test 'Test msvs-detect --installed'
./msvs-detect --installed

test 'Test msvs-detect --all'
./msvs-detect --all | tee all-compilers

test 'Ensure msvs-detect locates a compiler'
if "$WHICH" cl &> /dev/null ; then
  cl &> env-cl || true
fi
eval $(./msvs-detect)
display_env
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
  echo "First run: $(cat first-cl)"
  echo "Environment: $(cat env-cl)"
  echo "Second run: $(cat detected-cl)"
fi

if [[ $TEST_ENVIRONMENT -eq 1 ]] ; then
  test 'Ensure msvs-detect prefers the same release as the environment compiler'
  REQUIRED_RELEASE="$MSVS_NAME"
  if ! eval $(./msvs-detect --arch=x64); then
    echo 'msvs-detect failed to detect an x64 compiler'>&2
    exit 1
  elif [[ $MSVS_NAME != "$REQUIRED_RELEASE" ]]; then
    echo "Environment compiler: $REQUIRED_RELEASE">&2
    echo "Complementary x64 cl: $MSVS_NAME">&2
    echo 'These should be identical'>&2
    exit 1
  else
   display_env
  fi

  test 'Test msvs-promote-path'
  echo "link is currently: $("$WHICH" link)"
  eval $(./msvs-promote-path)
  echo "link is now: $("$WHICH" link)"
  if link --version &> /dev/null ; then
    exit 1
  fi
else
  matrix
fi
