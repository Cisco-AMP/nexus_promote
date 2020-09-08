# Nexus Promote
Promotes Nexus assets between repositories


## Setup
Run the following script to install all required dependencies:
```
script/bootstrap
```

Either create a `.env` file based off of [.env.template](.env.template) or pass in the required values as environment variables directly to the command.

You can use `.env.test.local` and `.env.production.local` to override local values in `.env` if you're working with more than one environment.


## Usage
To run the script:
```
bin/nexus_promote
```

View available options with:
```
bin/nexus_promote -h
```


## Tests
To run all, or a subset, of the unit tests run one of the following commands:
```
script/test
script/test [NAME_OF_DIRECTORY]
script/test [NAME_OF_FILE]
script/test [NAME_OF_FILE]:[LINE_NUMBER]
```

To run the functional tests use the following command:
```
NEXUS_USERNAME=[USERNAME] NEXUS_PASSWORD=[PASSWORD] script/functional_test 
```
