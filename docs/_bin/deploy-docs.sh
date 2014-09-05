#!/bin/bash -e

if [ -z "$1" ]; then 
    version="latest"
else
    version=$1
fi

druid=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)

if [ -n "$(git -C "$druid" status --porcelain --untracked-files=no)" ]; then
  echo "Working directory is not clean, aborting"
  exit 1
fi

branch=druid-$version
if [ "$version" == "latest" ]; then
  branch=master
fi

if [ -z "$(git tag -l "$branch")" ] && [ "$branch" != "master" ]; then
  echo "Version tag does not exist: druid-$version"
  exit 1;
fi

tmp=$(mktemp -d -t druid-docs-deploy)
target=$tmp/docs
src=$tmp/druid

echo "Using Version     [$version]"
echo "Working directory [$tmp]"

git clone -q --depth 1 git@github.com:druid-io/druid-io.github.io.git "$target"

remote=$(git -C "$druid" config --local --get remote.origin.url)
git clone -q --depth 1 --branch $branch $remote "$src"

mkdir -p $target/docs/$version
rsync -a --delete "$src/docs/content/" $target/docs/$version

# generate javadocs for releases (not for master)
if [ "$version" != "latest" ] ; then
  (cd $src && mvn javadoc:aggregate)
  mkdir -p $target/api/$version
  rsync -a --delete "$src/target/site/apidocs/" $target/api/$version
fi

updatebranch=update-docs-$version

git -C $target checkout -b $updatebranch
git -C $target add -A .
git -C $target commit -m "Update $version docs"
git -C $target push origin $updatebranch

if [ -n "$GIT_TOKEN" ]; then
curl -u "$GIT_TOKEN:x-oauth-basic" -XPOST -d@- \
     https://api.github.com/repos/druid-io/druid-io.github.io/pulls <<EOF
{
  "title" : "Update $version docs",
  "head"  : "$updatebranch",
  "base"  : "master"
}
EOF

else
  echo "GitHub personal token not provided, not submitting pull request"
  echo "Please go to https://github.com/druid-io/druid-io.github.io and submit a pull request from the \`$updatebranch\` branch"
fi

rm -rf $tmp
