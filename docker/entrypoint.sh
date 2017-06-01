#!/bin/bash

HELP_TEXT="

Arguments:  
	run_arches: Default. Run the Arches server  
	run_tests: Run unit tests  
	setup_arches: Delete any existing Arches database and set up a fresh one  
	-h or help: Display help text  
"

display_help() {
	echo "${HELP_TEXT}"
}



CUSTOM_SCRIPT_FOLDER=${CUSTOM_SCRIPT_FOLDER:-/docker/entrypoint}
APP_FOLDER=${ARCHES_ROOT}/${ARCHES_PROJECT}
BOWER_JSON_FOLDER=${APP_FOLDER}/${ARCHES_PROJECT}
DJANGO_PORT=${DJANGO_PORT:-8000}

cd_arches_root() {
	cd ${ARCHES_ROOT}
	echo "Current work directory: ${ARCHES_ROOT}"
}

cd_app_folder() {
	cd ${APP_FOLDER}
	echo "Current work directory: ${APP_FOLDER}"
}

cd_bower_folder() {
	cd ${BOWER_JSON_FOLDER}
	echo "Current work directory: ${BOWER_JSON_FOLDER}"
}

activate_virtualenv() {
	. ${WEB_ROOT}/ENV/bin/activate
}

init_arches() {
	if [[ "${FORCE_DB_INIT}" == "True" ]]; then
		echo ""
		echo "*** Warning: FORCE_DB_INIT = True ***"
		echo ""
		setup_arches
	elif db_exists; then
		echo "Database ${PGDBNAME} already exists, skipping initialization."
		echo ""
	else
		echo "Database ${PGDBNAME} does not exists yet, starting setup..."
		setup_arches
	fi

	init_arches_projects
}

db_exists() {
	echo "Checking if database "${PGDBNAME}" exists..."
	count=`psql -h ${PGHOST} -U postgres -Atc "SELECT COUNT(*) FROM pg_catalog.pg_database WHERE datname='${PGDBNAME}'"`

	# Check if returned value is a number and not some error message
	re='^[0-9]+$'
	if ! [[ ${count} =~ $re ]] ; then
	   echo "Error: Something went wrong when checking if database "${PGDBNAME}" exists..." >&2;
		 echo "Exiting..."
		 exit 1
	fi

	# Return 0 (= true) if database exists
	if [[ ${count} > 0 ]]; then
		return 0
	else
		return 1
	fi
}

setup_arches() {
	# Setup Postgresql and Elasticsearch (this deletes your existing database)

	echo "" && echo ""
	echo "*** Initializing database ***"
	echo ""
	echo "*** Any existing Arches database will be deleted ***"
	echo "" && echo ""

	echo "5" && sleep 1 && echo "4" && sleep 1 && echo "3" && sleep 1 && echo "2" && sleep 1 &&	echo "1" &&	sleep 1 && echo "0" && echo ""

	echo "Running: python manage.py packages -o setup"
	python manage.py packages -o setup


	if [[ "${INSTALL_DEFAULT_GRAPHS}" == "True" ]]; then
		# Import graphs
		if ! graphs_exist; then
			echo "Running: python manage.py packages -o import_graphs"
			python manage.py packages -o import_graphs
		else
			echo "Graphs already exist in the database. Skipping 'import_graphs'."
		fi
	fi


	if [[ "${INSTALL_DEFAULT_CONCEPTS}" == "True" ]]; then
		# Import concepts
		if ! concepts_exist; then
			import_reference_data arches/db/schemes/arches_concept_scheme.rdf
		else
			echo "Concepts already exist in the database."
			echo "Skipping 'arches_concept_scheme.rdf'."
			echo "Skipping 'cvast_concept_scheme.rdf'."
		fi

		# Import collections
		if ! collections_exist; then
			import_reference_data arches/db/schemes/arches_concept_collections.rdf
		else
			echo "Collections already exist in the database."
			echo "Skipping 'import_reference_data arches_concept_collections.rdf'."
		fi
	fi
}


init_arches_projects() {
	if [[ ! -z ${ARCHES_PROJECT} ]]; then
		echo "Checking if Arches project "${ARCHES_PROJECT}" exists..."
		if [[ ! -d ${APP_FOLDER} ]] || [[ ! "$(ls -A ${APP_FOLDER})" ]]; then
			echo ""
			echo "----- Custom Arches project '${ARCHES_PROJECT}' does not exist. -----"
			echo "----- Creating '${ARCHES_PROJECT}'... -----"
			echo ""

			arches-project create ${ARCHES_PROJECT} --directory ${ARCHES_PROJECT}

			exit_code=$?
			if [[ ${exit_code} != 0 ]]; then
				echo "Something went wrong when creating your Arches project: ${ARCHES_PROJECT}."
				echo "Exiting..."
				exit ${exit_code}
			fi

			copy_settings_local
		else
			echo "Custom Arches project '${ARCHES_PROJECT}' already exists."
		fi
	fi
}


db_exists() {
	echo "Checking if database "${PGDBNAME}" exists..."
	psql -lqt -h $PGHOST -U postgres | cut -d \| -f 1 | grep -qw ${PGDBNAME}
}

graphs_exist() {
	row_count=$(psql -h ${PGHOST} -U postgres -d ${PGDBNAME} -Atc "SELECT COUNT(*) FROM public.graphs")
	if [[ ${row_count} -le 3 ]]; then
		return 1
	else
		return 0
	fi
}

concepts_exist() {
	row_count=$(psql -h ${PGHOST} -U postgres -d ${PGDBNAME} -Atc "SELECT COUNT(*) FROM public.concepts WHERE nodetype = 'Concept'")
	if [[ ${row_count} -le 2 ]]; then
		return 1
	else
		return 0
	fi
}

collections_exist() {
	row_count=$(psql -h ${PGHOST} -U postgres -d ${PGDBNAME} -Atc "SELECT COUNT(*) FROM public.concepts WHERE nodetype = 'Collection'")
	if [[ ${row_count} -le 1 ]]; then
		return 1
	else
		return 0
	fi
}

import_reference_data() {
	# Import example concept schemes
	local rdf_file="$1"
	echo "Running: python manage.py packages -o import_reference_data -s \"${rdf_file}\""
	python manage.py packages -o import_reference_data -s "${rdf_file}"
}

copy_settings_local() {
	# The settings_local.py in ${ARCHES_ROOT}/arches/ gets ignored if running manage.py from a custom Arches project instead of Arches core app
	if [[ ! -f ${APP_FOLDER}/${ARCHES_PROJECT}/settings_local.py ]]; then
		echo "Copying ${ARCHES_ROOT}/arches/settings_local.py to ${APP_FOLDER}/${ARCHES_PROJECT}/settings_local.py..."
		cp ${ARCHES_ROOT}/arches/settings_local.py ${APP_FOLDER}/${ARCHES_PROJECT}/settings_local.py
	fi
}

set_dev_mode() {
	python ${ARCHES_ROOT}/setup.py develop
}

install_dev_requirements() {
	echo ""
	echo ""
	echo "----- INSTALLING DEV REQUIREMENTS -----"
	echo ""
	pip install -r ${ARCHES_ROOT}/arches/install/requirements_dev.txt
}

# This is also done in Dockerfile, but that does not include user's custom Arches app bower.json
# Also, the bower_components folder may have been overlaid by a Docker volume in a dev environment.
install_bower_components() {
	echo ""
	echo ""
	echo "----- INSTALLING BOWER COMPONENTS -----"
	echo ""
	bower --allow-root install
}

run_migrations() {
	echo ""
	echo ""
	echo "----- RUNNING DATABASE MIGRATIONS -----"
	echo ""
	python manage.py migrate
}

run_custom_scripts() {
	for file in ${CUSTOM_SCRIPT_FOLDER}/*; do
		if [[ -f ${file} ]]; then
			echo ""
			echo ""
			echo "----- RUNNING CUSTUM SCRIPT: ${file} -----"
			echo ""
			${file}
		fi
	done
}

collect_static(){
	echo ""
	echo ""
	echo "----- COLLECTING DJANGO STATIC FILES -----"
	echo ""
	python manage.py collectstatic --noinput
}

run_django_server() {
	echo ""
	echo ""
	echo "----- *** RUNNING DJANGO SERVER *** -----"
	echo ""
	if [[ ${DJANGO_NORELOAD} == "True" ]]; then
	    echo "Running Django with options --noreload --nothreading."
		exec python manage.py runserver --noreload --nothreading 0.0.0.0:${DJANGO_PORT}
	else
		exec python manage.py runserver 0.0.0.0:${DJANGO_PORT}
	fi
}



run_arches() {
	# Run first commands from ${ARCHES_ROOT}
	cd_arches_root
	init_arches

	if [[ "${DJANGO_MODE}" == "DEV" ]]; then
		set_dev_mode
		install_dev_requirements
	fi

	# Run from folder where user's bower.json lives
	cd_bower_folder
	install_bower_components

	# From here on, run from the user's ${APP_FOLDER}
	cd_app_folder

	if [[ "${DJANGO_MODE}" == "DEV" ]]; then
		run_migrations
	elif [[ "${DJANGO_MODE}" == "PROD" ]]; then
		collect_static
	fi

	run_custom_scripts

	run_django_server
}

run_tests() {
	cd_arches_root
	set_dev_mode
	install_dev_requirements
	echo ""
	echo ""
	echo "----- RUNNING ARCHES TESTS -----"
	echo ""
	python manage.py test tests --pattern="*.py" --settings="tests.test_settings" --exe
	if [ $? -ne 0 ]; then
        echo "Error: Not all tests ran succesfully."
		echo "Exiting..."
        exit 1
	fi
}

### Starting point ###

activate_virtualenv

# Use -gt 1 to consume two arguments per pass in the loop (e.g. each
# argument has a corresponding value to go with it).
# Use -gt 0 to consume one or more arguments per pass in the loop (e.g.
# some arguments don't have a corresponding value to go with it, such as --help ).

# If no arguments are supplied, assume the server needs to be run
if [[ $#  -eq 0 ]]; then
	run_arches
fi

# Else, process arguments
echo "Full command: $@"
while [[ $# -gt 0 ]]
do
	key="$1"
	echo "Command: ${key}"

	case ${key} in
		run_arches)
			wait_for_db
			run_arches
		;;
		setup_arches)
			wait_for_db
			setup_arches
		;;
		run_tests)
			wait_for_db
			run_tests
		;;
		help|-h)
			display_help
		;;
		*)
			exec "$@"
		;;
	esac
	shift # next argument or value
done

