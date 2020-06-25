#!/usr/bin/env bash

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
