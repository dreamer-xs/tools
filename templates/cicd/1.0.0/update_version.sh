#!/bin/bash

ABSOLUTE_PATH=$(dirname $0)
cd ${ABSOLUTE_PATH}
TMP_CONTENT_FILE="${ABSOLUTE_PATH}/tmp_sql_file_`date +%s`_$$"


#A_GIT_ADDR="http://${GIT_SERVER_DOMAIN}/svicloud/catalog.git"
#DEV_GIT_ADDR="http://${GIT_SERVER_DOMAIN}/svicloud/wisecloud-dev.git"
#TEST_GIT_ADDR="http://${GIT_SERVER_DOMAIN}/svicloud/wisecloud-test.git"
#PRO_GIT_ADDR="http://${GIT_SERVER_DOMAIN}/svicloud/wisecloud-pro.git"
TIMESTAMP=`date +%Y-%m-%d' '%H:%M:%S`

function PRINT_LOG()
{
    local level=$1
    shift
    local info=$@

    if [ -z "${level}" ]
    then
        level=INFO
    fi

    echo "[${TIMESTAMP}] [$$] ${level} ${info}"
}

function fn_git_clone()
{
    #note:del dir before clone
    [ -d "${GIT_PROJECT}" ] && rm -rf ${GIT_PROJECT}

    git config --global user.email dongchaojun@svi-tech.com.cn
    git config --global user.name  svicloud
    git clone ${GIT_ADDR}

    if [ $? -ne 0 ]
    then
        PRINT_LOG "FATAL" "Failed to git clone code!"
        return 1
    fi

    PRINT_LOG "INFO" "Success to clone code"
}

function fn_git_push()
{

    #note:push code use expect
(
cat << EOF
#!/usr/bin/expect
spawn git push
expect "Username for 'http://${GIT_SERVER_DOMAIN}':"
send "${GIT_USER}\r"
expect "Password for 'http://svicloud@${GIT_SERVER_DOMAIN}':"
send "${GIT_PVALUE}\r"
expect eof
exit
EOF
) > ./${GIT_PROJECT}/git_push.expect

    cd ${GIT_PROJECT}
    git add -A *
    git commit -m ${MODULE_VERSION}
    expect  git_push.expect
    cd -

    if [ $? -ne 0 ]
    then
        PRINT_LOG "FATAL" "Failed to git push code!"
        return 1
    fi

    [ -d "${GIT_PROJECT}" ] && rm -rf ${GIT_PROJECT}

    PRINT_LOG "INFO" "Success to push code"
}


function fn_modify_version()
{
    
    local all_module_name=("authcenter" "cas" "dcmp" "ues")
    local index=0

    #note:flush rancher version that can be display in web site
    while [ ${index} -lt ${#all_module_name[@]} ]
    do
        local module_code_path="catalog/templates/${all_module_name[${index}]}"

        PRINT_LOG "INFO" "module_code_path=${module_code_path}"

        #old_module_version_dir=`find ${module_code_path}/ -type d -exec basename {} \; | sort -n |tail -1`
        old_module_version_dir="${module_code_path}/example"

        if [ -z "${old_module_version_dir}" ]
        then
            PRINT_LOG "FATAL" "Failed to get module dir or module dir<${old_module_version_dir}> is exist"
            return 1
        fi

        [ -d "${module_code_path}/${MODULE_VERSION}" ] && rm -rf ${module_code_path}/${MODULE_VERSION}

        PRINT_LOG "INFO" "old_module_version_dir=${old_module_version_dir} new_dir=${module_code_path}/${MODULE_VERSION}"

        cp -rf ${old_module_version_dir} ${module_code_path}/${MODULE_VERSION}

        find ${module_code_path}/${MODULE_VERSION}/ -type f  -name "*.yml" | while read file
        do
            #sed -i "s#version.*[v|V].*[r|R].*#version : ${MODULE_VERSION}#g" ${file}
            #sed -i "s#version : v1.1.1#version : ${MODULE_VERSION}#g" ${file}
            sed -i "s#@{VERSION}#${MODULE_VERSION}#g" ${file}

            if [ $? -eq 0 ]
            then
                PRINT_LOG "INFO" "Sucess to modidy file<${file}>."
            else
                PRINT_LOG "INFO" "Failed to modidy file<${file}>!"
                break
            fi
        done

        #note:modify service version, display the latest version in the svicloud web site
        sed -i "s#version.*#version : ${MODULE_VERSION}#g" ${module_code_path}/config.yml

        let index++
    done

}

function fn_git_del_version()
{
    local module_name=$1
    local version=$2


    local module_version="${GIT_PROJECT}/templates/${module_name}/${version}"

    PRINT_LOG "INFO" "module_version=${module_version}"

    if [ -d "${module_version}" ]
    then
        cd ${GIT_PROJECT}/templates/${module_name}

        [ -n "${version}" ] && git rm -rf ${version}

        cd -

        PRINT_LOG "INFO" "Successto delete module_version<${module_version}>"
    else
        PRINT_LOG "INFO" "The module_version<${module_version}> is not exist"
        return 1
    fi

    return 0

}


function fn_git_add_version()
{
    local module_name=$1
    local version=$2

    local module_version="${GIT_PROJECT}/templates/${module_name}/${version}"

    PRINT_LOG "INFO" "module_version=${module_version}"

    module_version_example="${GIT_PROJECT}/templates/${module_name}/example"

    if [ -z "${module_version_example}" ]
    then
        PRINT_LOG "FATAL" "The module dir<${module_version_example}> is not exist"
        return 1
    fi

    [ -d "${module_version}" ] && rm -rf ${module_version}

    cp -rf ${module_version_example} ${module_version}

    find ${module_version}/ -type f  -name "*.yml" | while read file
    do
        sed -i "s#@{VERSION}#${version}#g" ${file}
        [ -n "${PC_VERSION}" ] && sed -i "s#@{PC_VERSION}#${PC_VERSION}#g" ${file}
        [ -n "${SERVER_VERSION}" ] && sed -i "s#@{SERVER_VERSION}#${SERVER_VERSION}#g" ${file}
        [ -n "${WEB_VERSION}" ] && sed -i "s#@{WEB_VERSION}#${WEB_VERSION}#g" ${file}

       #if [ $? -eq 0 ]
       #then
       #    PRINT_LOG "INFO" "Sucess to modidy file<${file}>."
       #else
       #    PRINT_LOG "INFO" "Failed to modidy file<${file}>!"
       #    break
       #fi
    done

    #note:modify service version, display the latest version in the svicloud web site
    sed -i "s#version.*#version : ${version}#g" ${module_version}/../config.yml

}

function fn_check_parameter()
{
    local all_module_name=("authcenter" "cas" "dcmp" "ues")

    local index=0

    echo ${MODULE_VERSION} | egrep "*[v|V].*[r|R].*" &>/dev/null

    if [ $? -ne 0 ]
    then
        PRINT_LOG "FATAL" "The module version <${MODULE_VERSION}> is invalid!"
        return 1
    fi


    #note:flush rancher version that can be display in web site
    while [ ${index} -lt ${#all_module_name[@]} ]
    do
        if [ "${all_module_name[${index}]}" = "${MODULE_NAME}" ]
        then
            break
        fi

        let index++
    done

    if [ ${#all_module_name[@]} -eq ${index} ]
    then
        PRINT_LOG "FATAL" "The module name<${MODULE_NAME}> is invalid!"
        return 1
    fi

    return 0
}

function fn_usage()
{
    echo -e "\n"
    echo -e "  Usage:"
    echo -e "\n"
    echo -e "    This script is update or delete module version from svicloud app store"
    echo -e "\n"
    echo -e "    Options:"
    echo -e "    -a, action                   Script action [ add | del ], necessary!"
    echo -e "    -n, module name              Specify the module name, necessary!"
    echo -e "    -v, module version           Specify the module version, necessary!"
    echo -e "\n"
    echo -e "    -p, git project              Specify the svicloud app store git project name"
    echo -e "    -h, git server domain        Specify the app store git project domain"
    echo -e "    -u, git user                 Specify the app store git project user"
    echo -e "    -P, git Password             Specify the app store git project password"
    echo -e "    -f, parameter config file    Specify the all parameter config key"
    echo -e "\n"

    exit 1

}

function fn_get_parameter()
{
    while getopts "a:n:v:p:h:u:P" opt; do
        case $opt in
            a)
                echo "this is -a the arg is ! $OPTARG"
                export ACTION=${OPTARG}
                ;;
            n)
                echo "this is -n the arg is ! $OPTARG"
                export MODULE_NAME=${OPTARG}
                ;;
            v)
                echo "this is -v the arg is ! $OPTARG"
                export MODULE_VERSION=${OPTARG}
                ;;
            p)
                echo "this is -p the arg is ! $OPTARG"
                export GIT_PROJECT=${OPTARG}
                ;;
            h)
                echo "this is -h the arg is ! $OPTARG"
                export GIT_SERVER_DOMAIN=${OPTARG}
                ;;
            u)
                echo "this is -u the arg is ! $OPTARG"
                export GIT_USER=${OPTARG}
                ;;
            P)
                echo "this is -P the arg is ! $OPTARG"
                export GIT_PVALUE=${OPTARG}
                ;;
            *)
                return 1
                ;;
        esac
    done

}

function fn_main()
{
    [ -z "$@" ] && fn_usage

    fn_get_parameter $@  &>/dev/null

    [ $? -ne 0 ] && fn_usage

    #note:git server version
    [ -z "${GIT_PROJECT}" ] && GIT_PROJECT="wisecloud-test"
    [ -z "${GIT_SERVER_DOMAIN}" ] && GIT_SERVER_DOMAIN="192.168.1.114"
    [ -z "${GIT_USER}" ] && GIT_USER="svicloud"
    [ -z "${GIT_PVALUE}" ] && GIT_PVALUE="mogK+vXX"

    GIT_ADDR="http://${GIT_SERVER_DOMAIN}/svicloud/${GIT_PROJECT}.git"


    fn_check_parameter || return $?

    PRINT_LOG "INFO" "$0 $@"

    fn_git_clone || return $?

    case ${ACTION} in
        add)
            fn_git_add_version "${MODULE_NAME}" "${MODULE_VERSION}" || return $?
            ;;
        del)
            fn_git_del_version "${MODULE_NAME}" "${MODULE_VERSION}" || return $?
            ;;
        *)
            fn_usage
            ;;
    esac

    fn_git_push || return $?
}

fn_main $@
exit $?


