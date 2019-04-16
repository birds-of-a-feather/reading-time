#!groovy
import groovy.json.JsonOutput
import groovy.json.JsonSlurper

/*
Environment variables: These environment variables should be set in Jenkins in: `https://github-demo.ci.cloudbees.com/job/<org name>/configure`:

For deployment purposes:
 - HEROKU_PREVIEW=<your heroku preview app>
 - HEROKU_PRODUCTION=<your heroku production app>

Please also add the following credentials to the global domain of your organization's folder:
- Heroku API key as secret text with ID 'HEROKU_API_KEY'
- GitHub Token value as secret text with ID 'GITHUB_TOKEN'
*/

pipeline {
  // Run everything on an existing agent configured with a label 'docker'.
  // This agent will need docker, git and a jdk installed at a minimum.
  agent {
    docker {
      image 'maven:3.3.9-jdk-8-alpine'
      args '--entrypoint=""'
    }
  }
  stages {
    stage('Build') {
      steps {
        sh 'mvn clean install -DskipTests=true -Dmaven.javadoc.skip=true -Dcheckstyle.skip=true -B -V'
        stash includes: '**/target/*.jar', name: 'app'
      }
      post {
        success {
          // we only worry about archiving the jar file if the build steps are successful
          archiveArtifacts(artifacts: '**/target/*.jar', allowEmptyArchive: true)
        }
      }
    }
    stage('Unit Tests') {
      steps {
        unitTest()
      }
    }
    stage('Quality Tests') {
      steps {
        lintTest()
      }
    }
    stage('Deploy') {
      environment {
        HEROKU_PREVIEW='jenkins-daze-preview'
        HEROKU_PRODUCTION='jenkins-daze-demo'
      }
      steps {
        deploy()
      }
    }
  }
}

def printOptions() {
    echo "====Environment variable configurations===="
    echo sh(script: 'env|sort', returnStdout: true)
}

def isPRMergeBuild() {
    return (env.BRANCH_NAME ==~ /^PR-\d+$/)
}

def build() {
    stage 'Build'
    sh 'mvn clean install -DskipTests=true -Dmaven.javadoc.skip=true -Dcheckstyle.skip=true -B -V'
}

def unitTest() {
    // stage 'Unit tests'
    sh 'mvn test -B -Dmaven.javadoc.skip=true -Dcheckstyle.skip=true'
    if (currentBuild.result == "UNSTABLE") {
        sh "exit 1"
    }
}

def allTests() {
    stage 'All tests'
    // don't skip anything
    sh 'mvn test -B'
    step([$class: 'JUnitResultArchiver', testResults: '**/target/surefire-reports/TEST-*.xml'])
    if (currentBuild.result == "UNSTABLE") {
        // input "Unit tests are failing, proceed?"
        sh "exit 1"
    }
}

def allCodeQualityTests() {
    lintTest()
}

def lintTest() {

    if (env.DEMO_DISABLE_LINT == "true") {
        return
    }

    stage 'Code Quality - Linting'
    context="continuous-integration/jenkins/linting"
    setBuildStatus ("${context}", 'Checking code conventions', 'PENDING')
    lintTestPass = true

    try {
        sh 'mvn verify -DskipTests=true'
    } catch (err) {
        setBuildStatus ("${context}", 'Some code conventions are broken', 'FAILURE')
        lintTestPass = false
    } finally {
        if (lintTestPass) setBuildStatus ("${context}", 'Code conventions OK', 'SUCCESS')
    }
}

def preview() {

    if (env.DEMO_DISABLE_PREVIEW == "true") {
        return
    }

    stage name: 'Deploy to Preview env', concurrency: 1
    step([$class: 'ArtifactArchiver', artifacts: '**/target/*.jar', fingerprint: true])
    def herokuApp = "${env.HEROKU_PREVIEW}"
    def id = createDeployment(getBranch(), "preview", "Deploying branch to test")
    echo "Deployment ID: ${id}"
    if (id != null) {
        setDeploymentStatus(id, "pending", "https://${herokuApp}.herokuapp.com/", "Pending deployment to test");
        herokuDeploy "${herokuApp}"
        echo "app deployed to Heroku"
        setDeploymentStatus(id, "success", "https://${herokuApp}.herokuapp.com/", "Successfully deployed to test");
    }
}

def preProduction() {

    if (env.DEMO_DISABLE_PREPROD == "true") {
        return
    }

    stage name: 'Deploy to Pre-Production', concurrency: 1
    switchSnapshotBuildToRelease()
    herokuDeploy "${env.HEROKU_PREPRODUCTION}"
}

def manualPromotion() {

    if (env.DEMO_DISABLE_PROD == "true") {
        return
    }

    // we need a first milestone step so that all jobs entering this stage are tracked an can be aborted if needed
    milestone 1
    // time out manual approval after ten minutes
    timeout(time: 10, unit: 'MINUTES') {
        input message: "Does Pre-Production look good?"
    }
    // this will kill any job which is still in the input step
    milestone 2
}

def deploy() {
    if  (env.BRANCH_NAME != 'master') {
        preview()
    }
    else {
        production()
    }
}

def production() {

    if (env.DEMO_DISABLE_PROD == "true") {
        return
    }

    echo '<------ here ------>'
    echo "${env.HEROKU_PRODUCTION}"
    stage name: 'Deploy to Production', concurrency: 1
    step([$class: 'ArtifactArchiver', artifacts: '**/target/*.jar', fingerprint: true])
    herokuDeploy "${env.HEROKU_PRODUCTION}"
    def version = getCurrentHerokuReleaseVersion("${env.HEROKU_PRODUCTION}")
    def createdAt = getCurrentHerokuReleaseDate("${env.HEROKU_PRODUCTION}", version)
    echo "Release version: ${version}"
    createRelease(version, createdAt)
}

def switchSnapshotBuildToRelease() {
    descriptor.version = '1.0.0'
    descriptor.pomFile = 'pom.xml'
    descriptor.transform()
}

def herokuDeploy (herokuApp) {
    echo "deploying: ${herokuApp}"
    withCredentials([[$class: 'StringBinding', credentialsId: 'HEROKU_API_KEY', variable: 'HEROKU_API_KEY']]) {
        sh "mvn clean heroku:deploy -DskipTests=true -Dmaven.javadoc.skip=true -Dheroku.logProgress -B -V -D heroku.appName=${herokuApp}"
    }
}

def getRepoSlug() {
    tokens = "${env.JOB_NAME}".tokenize('/')
    org = tokens[tokens.size()-3]
    repo = tokens[tokens.size()-2]
    return "githubcustomers/reading-time"
    //return "${org}/${repo}"
}

def getBranch() {
    tokens = "${env.JOB_NAME}".tokenize('/')
    branch = tokens[tokens.size()-1]
    return "${branch}"
}

def createDeployment(ref, environment, description) {
    withCredentials([[$class: 'StringBinding', credentialsId: 'GITHUB_TOKEN', variable: 'GITHUB_TOKEN']]) {
        def payload = JsonOutput.toJson(["ref": "${ref}", "description": "${description}", "environment": "${environment}", "required_contexts": []])
        def apiUrl = "https://api.github.com/repos/${getRepoSlug()}/deployments"
        def response = sh(returnStdout: true, script: "curl -s -H \"Authorization: Token ${env.GITHUB_TOKEN}\" -H \"Accept: application/json\" -H \"Content-type: application/json\" -X POST -d '${payload}' ${apiUrl}").trim()
        def jsonSlurper = new JsonSlurper()
        def data = jsonSlurper.parseText("${response}")
        return data.id
    }
}

void createRelease(tagName, createdAt) {
    echo "creating release"
    withCredentials([[$class: 'StringBinding', credentialsId: 'GITHUB_TOKEN', variable: 'GITHUB_TOKEN']]) {
        def body = "**Created at:** ${createdAt}\n**Deployment job:** [${env.BUILD_NUMBER}](${env.BUILD_URL})\n**Environment:** [${env.HEROKU_PRODUCTION}](https://dashboard.heroku.com/apps/${env.HEROKU_PRODUCTION})"
        def payload = JsonOutput.toJson(["tag_name": "v${tagName}", "name": "${env.HEROKU_PRODUCTION} - v${tagName}", "body": "${body}"])
        def apiUrl = "https://api.github.com/repos/${getRepoSlug()}/releases"
        def response = sh(returnStdout: true, script: "curl -s -H \"Authorization: Token ${env.GITHUB_TOKEN}\" -H \"Accept: application/json\" -H \"Content-type: application/json\" -X POST -d '${payload}' ${apiUrl}").trim()
    }
}

void setDeploymentStatus(deploymentId, state, targetUrl, description) {
    echo "setting deployment status"
    withCredentials([[$class: 'StringBinding', credentialsId: 'GITHUB_TOKEN', variable: 'GITHUB_TOKEN']]) {
        def payload = JsonOutput.toJson(["state": "${state}", "target_url": "${targetUrl}", "description": "${description}"])
        def apiUrl = "https://api.github.com/repos/${getRepoSlug()}/deployments/${deploymentId}/statuses"
        def response = sh(returnStdout: true, script: "curl -s -H \"Authorization: Token ${env.GITHUB_TOKEN}\" -H \"Accept: application/json\" -H \"Content-type: application/json\" -X POST -d '${payload}' ${apiUrl}").trim()
        echo "deployment response: ${response}"
    }
}

void setBuildStatus(context, message, state) {
    // partially hard coded URL because of https://issues.jenkins-ci.org/browse/JENKINS-36961, adjust to your own GitHub instance
    step([
            $class: "GitHubCommitStatusSetter",
            contextSource: [$class: "ManuallyEnteredCommitContextSource", context: context],
            reposSource: [$class: "ManuallyEnteredRepositorySource", url: "https://github.com/${getRepoSlug()}"],
            errorHandlers: [[$class: "ChangingBuildStatusErrorHandler", result: "UNSTABLE"]],
            statusResultSource: [ $class: "ConditionalStatusResultSource", results: [[$class: "AnyBuildResult", message: message, state: state]] ]
    ]);
    echo 'set status'
}

def getCurrentHerokuReleaseVersion(app) {
    echo "getting Heroku Release version"
    withCredentials([[$class: 'StringBinding', credentialsId: 'HEROKU_API_KEY', variable: 'HEROKU_API_KEY']]) {
        def apiUrl = "https://api.heroku.com/apps/${app}/dynos"
        def response = sh(returnStdout: true, script: "curl -s  -H \"Authorization: Bearer ${env.HEROKU_API_KEY}\" -H \"Accept: application/vnd.heroku+json; version=3\" -X GET ${apiUrl}").trim()
        def jsonSlurper = new JsonSlurper()
        def data = jsonSlurper.parseText("${response}")
        return data[0].release.version
    }
}

def getCurrentHerokuReleaseDate(app, version) {
    echo "getting Heroku Release Date"
    withCredentials([[$class: 'StringBinding', credentialsId: 'HEROKU_API_KEY', variable: 'HEROKU_API_KEY']]) {
        def apiUrl = "https://api.heroku.com/apps/${app}/releases/${version}"
        def response = sh(returnStdout: true, script: "curl -s  -H \"Authorization: Bearer ${env.HEROKU_API_KEY}\" -H \"Accept: application/vnd.heroku+json; version=3\" -X GET ${apiUrl}").trim()
        def jsonSlurper = new JsonSlurper()
        def data = jsonSlurper.parseText("${response}")
        return data.created_at
    }
}
