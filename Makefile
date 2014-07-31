# This file is part of LIO(tm).
# Copyright (c) 2011-2014 by Datera, Inc
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may
# not use this file except in compliance with the License. You may obtain
# a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
#     Unless required by applicable law or agreed to in writing, software
#     distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
#     WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
#     License for the specific language governing permissions and limitations
#     under the License.
#

NAME = rtslib
GIT_BRANCH = $$(git branch | grep \* | tr -d \*)
GIT_DESC = $$(basename $$(git describe --tags | grep -o '[0-9].*$$'))
GIT_LAST_TAG = $$(git describe --tags --abbrev=0 | grep -o '[0-9].*$$')
GIT_PKG_TAG = $$(echo $(GIT_LAST_TAG) | tr - \~)
VERSION = $$(echo $(GIT_DESC) | sed s/^$(GIT_LAST_TAG)/$(GIT_PKG_TAG)/)

version:
	@echo $(VERSION)

all:
	@echo "Usage:"
	@echo
	@echo "  make deb         - Builds debian packages."
	@echo "  make debinstall  - Builds and installs debian packages."
	@echo "                     (requires sudo access)"
	@echo "  make rpm         - Builds rpm packages."
	@echo "  make release     - Generates the release tarball."
	@echo
	@echo "  make test   	  - Runs the safe tests suite."
	@echo "  make test-all 	  - Runs all tests, including dangerous system test."
	@echo "                     This WILL mess-up your system target configuration!"
	@echo "                     Requires sudo access to root privileges."
	@echo
	@echo "  make clean       - Cleanup the local repository build files."
	@echo "  make cleanall    - Also remove dist/*"

test:
	@echo "Running the safe tests suite..."
	@(PYTHONPATH=$$(pwd); cd tests/safe ; python -u -m unittest discover)

test-all: test
	@if [ ! -d "/sys/kernel/config/target" ]; then \
		echo "Cannot run system tests, target is stopped."; \
		exit 1; \
	fi
	@echo "Will run the DESTRUCTIVE system tests suite now."
	@echo "This requires sudo access to root privileges."
	@echo "These tests WILL mess-up your system target configuration!"
	@echo "Type CTRL-C to abort now or enter to continue..."
	@read X
	@(PYTHONPATH=$$(pwd); cd tests/system ; sudo python -m unittest discover)

clean:
	@rm -fv ${NAME}/*${NAME}/*.html
	@rm -frv doc
	@rm -frv ${NAME}.egg-info MANIFEST build
	@rm -frv debian/tmp
	@rm -fv build-stamp
	@rm -fv dpkg-buildpackage.log dpkg-buildpackage.version
	@rm -frv *.rpm
	@rm -fv debian/files debian/*.log debian/*.substvars
	@rm -frv debian/${NAME}-doc/ debian/python2.5-${NAME}/
	@rm -frv debian/python2.6-${NAME}/ debian/python-${NAME}/
	@rm -frv results
	@rm -fv rpm/*.spec *.spec rpm/sed* sed*
	@rm -frv ${NAME}-*
	@find . -name *.swp -exec rm -v {} \;
	@find . -name *.pyc -exec rm -vf {} \;
	@find . -name *~ -exec rm -v {} \;
	@find . -name \#*\# -exec rm -v {} \;
	@echo "Finished cleanup."

cleanall: clean
	@rm -frv dist

release: build/release-stamp
build/release-stamp:
	@mkdir -p build
	@echo "Exporting the repository files..."
	@git archive ${GIT_BRANCH} --prefix ${NAME}-${VERSION}/ \
		| (cd build; tar xfp -)
	@cp -pr debian/ build/${NAME}-${VERSION}
	@echo "Cleaning up the target tree..."
	@rm -f build/${NAME}-${VERSION}/Makefile
	@rm -f build/${NAME}-${VERSION}/.gitignore
	@echo "Fixing version string..."
	@sed -i "s/__version__ = .*/__version__ = '${VERSION}'/g" \
		build/${NAME}-${VERSION}/${NAME}/__init__.py
	@echo "Generating rpm specfile from template..."
	@cd build/${NAME}-${VERSION}; \
		for spectmpl in rpm/*.spec.tmpl; do \
			sed -i "s/Version:\( *\).*/Version:\1${VERSION}/g" $${spectmpl}; \
			mv $${spectmpl} $$(basename $${spectmpl} .tmpl); \
		done; \
		rm -r rpm
	@echo "Generating rpm changelog..."
	@( \
		version=$(VERSION); \
		author=$$(git show HEAD --format="format:%an <%ae>" -s); \
		date=$$(git show HEAD --format="format:%ad" -s \
			| awk '{print $$1,$$2,$$3,$$5}'); \
		hash=$$(git show HEAD --format="format:%H" -s); \
	   	echo '* '"$${date} $${author} $${version}-1"; \
		echo "  - Generated from git commit $${hash}."; \
	) >> $$(ls build/${NAME}-${VERSION}/*.spec)
	@echo "Generating debian changelog..."
	@( \
		version=$(VERSION); \
		author=$$(git show HEAD --format="format:%an <%ae>" -s); \
		date=$$(git show HEAD --format="format:%aD" -s); \
		day=$$(git show HEAD --format='format:%ai' -s \
			| awk '{print $$1}' \
			| awk -F '-' '{print $$3}' | sed 's/^0/ /g'); \
		date=$$(echo $${date} \
			| awk '{print $$1, "'"$${day}"'", $$3, $$4, $$5, $$6}'); \
		hash=$$(git show HEAD --format="format:%H" -s); \
	   	echo "${NAME} ($${version}) unstable; urgency=low"; \
		echo; \
		echo "  * Generated from git commit $${hash}."; \
		echo; \
		echo " -- $${author}  $${date}"; \
		echo; \
	) > build/${NAME}-${VERSION}/debian/changelog
	@find build/${NAME}-${VERSION}/ -exec \
		touch -t $$(date -d @$$(git show -s --format="format:%at") \
			+"%Y%m%d%H%M.%S") {} \;
	@mkdir -p dist
	@cd build; tar -c --owner=0 --group=0 --numeric-owner \
		--format=gnu -b20 --quoting-style=escape \
		-f ../dist/${NAME}-${VERSION}.tar \
		$$(find ${NAME}-${VERSION} -type f | sort)
	@gzip -6 -n dist/${NAME}-${VERSION}.tar
	@echo "Generated release tarball:"
	@echo "    $$(ls dist/${NAME}-${VERSION}.tar.gz)"
	@touch build/release-stamp

deb: release build/deb-stamp
build/deb-stamp:
	@echo "Building debian packages..."
	@cd build/${NAME}-${VERSION}; \
		dpkg-buildpackage -rfakeroot -us -uc
	@mv build/*_${VERSION}_*.deb dist/
	@echo "Generated debian packages:"
	@for pkg in $$(ls dist/*_${VERSION}_*.deb); do echo "  $${pkg}"; done
	@touch build/deb-stamp

debinstall: deb
	@echo "Installing $$(ls dist/*_${VERSION}_*.deb)"
	@sudo dpkg -i $$(ls dist/*_${VERSION}_*.deb)

rpm: release build/rpm-stamp
build/rpm-stamp:
	@echo "Building rpm packages..."
	@mkdir -p build/rpm
	@build=$$(pwd)/build/rpm; dist=$$(pwd)/dist/; rpmbuild \
		--define "_topdir $${build}" --define "_sourcedir $${dist}" \
		--define "_rpmdir $${build}" --define "_buildir $${build}" \
		--define "_srcrpmdir $${build}" -ba build/${NAME}-${VERSION}/*.spec
	@mv build/rpm/*-${VERSION}*.src.rpm dist/
	@mv build/rpm/*/*-${VERSION}*.rpm dist/
	@echo "Generated rpm packages:"
	@for pkg in $$(ls dist/*-${VERSION}*.rpm); do echo "  $${pkg}"; done
	@touch build/rpm-stamp
