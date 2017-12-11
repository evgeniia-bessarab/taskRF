*** Settings ***
Documentation     Перед запуском тестов необходимо:
...               pip install -U robotframework-databaselibrary
...               pip install -U requests
...               pip install -U robotframework-requests
Library           DatabaseLibrary
Library           OperatingSystem
Library           HttpLibrary.HTTP
Library           Collections
Library           String
Library           RequestsLibrary

*** Variables ***
${DBPath}         ../dockerEnv/web
${DBName}         clients
${TestUserInfoName}    Ivan Ivanovich
${Port}           5000
${Host}           localhost

*** Test Cases ***
Step 1. Connect to SQLiteDB
    [Tags]    db    smoke
    Connect To Database Using Custom Params    sqlite3    database="./${DBPath}/${DBName}.db", isolation_level=None
    Check If Exists In Database    select * from clients
    Check If Exists In Database    select * from balances

Step 2. Select clients with positive balance
    [Tags]    db    smoke
    ${output} =    Query    select count(*) from clients cl, balances bl where cl.client_id=bl.clients_client_id and bl.balance>0
    Run Keyword If    ${output}!=0    Add personif there no clients with positive balance
    @{queryResults} =    Query    select cl.client_id, bl.balance from clients cl, balances bl where cl.client_id=bl.clients_client_id and bl.balance>0 ORDER BY cl.client_id DESC LIMIT 1;
    Set Suite Variable    ${clientId}    ${queryResults[0][0]}
    Set Suite Variable    ${balanceId}    ${queryResults[0][1]}

Step 3. Get list of enable services for client
    [Tags]    http    smoke
    Create Session    server    http://${Host}:${Port}
    &{data}=    Create Dictionary    client_id    ${clientId}
    &{headers}=    Create Dictionary    Content-Type=application/json
    ${resp}=    Post Request    server    /client/services    data=${data}    headers=${headers}
    Should Be Equal As Strings    ${resp.status_code}    200
    ${listOfEnableClientServices} =    Create List
    : FOR    ${item}    IN    @{resp.json()['items']}
    \    Log    ${item['id']}
    \    Append To List    ${listOfEnableClientServices}    ${item['id']}
    Set Suite Variable    ${listOfEnableClientServicesTest}    ${listOfEnableClientServices}
    Log    ${listOfEnableClientServices}
    Comment    Create HTTP Context    ${Host}    http
    Comment    Set Request Body    {"client_id":${clientId}}
    Comment    Set Request Header    Content-Type    application/json
    Comment    POST    http://${Host}:${Port}/client/services
    Comment    Response Status Code Should Equal    200
    Comment    ${body}=    Get Response Body
    Comment    Log    ${body}
    Comment    Set Suite Variable    ${balanceIdResp}    Get Json Value    ${body}    /items/0/cost
    Comment    Set Suite Variable    ${clientIdResp}    Get Json Value    ${body}    /items/0/id
    Comment    Set Suite Variable    ${serviceName}    Get Json Value    ${body}    /items/0/name
    Comment    Should Be Equal    ${balanceIdResp}    ${clientId}
    Comment    Should Be Equal    ${clientIdResp}    ${balanceId}

Step 4. Get list of all available services
    [Tags]    http    smoke
    ${allAvailableServices}=    Create List
    Create HTTP Context    ${Host}    http
    Set Request Header    Content-Type    application/json
    HttpLibrary.HTTP.GET    http://${Host}:${Port}/services
    Response Status Code Should Equal    200
    ${respBody}=    Get Response Body
    ${bodyItems}    Get Json Value    ${respBody}    /items
    ${bodyCountItems}    Get Json Value    ${respBody}    /count
    @{bodyItems} =    Split String    ${bodyItems}    },
    Set Suite Variable    ${lengthListItems}    0
    : FOR    ${item}    IN    @{bodyItems}
    \    ${test}    Get Json Value    ${respBody}    /items/${lengthListItems}/id
    \    Append To List    ${allAvailableServices}    ${test}
    \    ${lengthListItems}=    Evaluate    ${lengthListItems}+1
    Should Be Equal As Integers    ${bodyCountItems}    ${lengthListItems}
    Log    ${allAvailableServices}
    Set Suite Variable    ${allAvailableServicesTest}    ${allAvailableServices}

Step 5. Find not connected client's service in list of all available services. Fix service's id and cost.
    : FOR    ${ELEMENT}    IN    ${listOfEnableClientServicesTest}
    \    Remove Values From List    ${allAvailableServicesTest}    ${ELEMENT}
    Set Suite Variable    ${notConnectedService}    ${allAvailableServicesTest[0]}
    @{queryResults}=    Query    select s.cost from SERVICES s \ where service_id=${allAvailableServicesTest[0]}
    Set Suite Variable    ${notConnectedServiceCost}    ${queryResults[0][0]}

Step 6. Connect service to client, do POST query http://localhost:{port}/client/add_service.
    [Tags]    http    smoke
    Create Session    server    http://${Host}:${Port}
    Log    ${clientId}
    Log    ${notConnectedService}
    &{data}=    Create Dictionary    client_id    ${clientId}    service_id    ${notConnectedService}
    &{headers}=    Create Dictionary    Content-Type=application/json
    ${resp}=    Post Request    server    /client/add_service    data=${data}    headers=${headers}
    Should Be Equal As Strings    ${resp.status_code}    202
    Should Be Equal As Strings    ${resp.content}    Processing
    Comment    Create HTTP Context    ${Host}    http
    Comment    Set Request Header    Content-Type    application/json
    Comment    ${dict}=    Create Dictionary    client_id    ${clientId}    service_id    ${notConnectedService}
    Comment    ${requestBody}=    Stringify Json    ${dict}
    Comment    Set Request Body    ${requestBody}
    Comment    POST    http://${Host}:${Port}/client/add_service
    Comment    Response Status Code Should Equal    202

Step 7. Wait until new service wouldn't connected. Max waiting time - 1 min, otherwise test caseis failed.
    [Tags]    http    smoke
    ${result} =    Wait Until Keyword Succeeds    60x    1s    Is new service available    ${notConnectedService}

Step 8. Get client balance from DB . Get final client balance
    [Tags]    db    smoke
    @{queryResults}=    Query    select bl.balance from clients cl, balances bl where cl.client_id=${clientId}
    Set Suite Variable    ${lastBalanceIdFromDB}    ${queryResults[0][0]}
    Log    ${lastBalanceIdFromDB}

Step 9. Compare values. : {last balance} = {first balance} - {service's cost}
    ${diff}    Evaluate    ${balanceId} - ${notConnectedServiceCost}
    Should Be Equal As Strings    ${lastBalanceIdFromDB}    ${diff}

*** Keywords ***
Add personif there no clients with positive balance
    Execute SQL String    SAVEPOINT first
    Execute SQL String    INSERT INTO CLIENTS (CLIENT_NAME) VALUES ('${TestUserInfoName}');
    Execute SQL String    INSERT INTO BALANCES (CLIENTS_CLIENT_ID, BALANCE) VALUES (last_insert_rowid(), '5');
    Check If Exists In Database    SELECT * FROM clients WHERE CLIENT_NAME = '${TestUserInfoName}';

Is new service available
    [Arguments]    ${idServices}
    Log    ${idServices}
    Create Session    server    http://${Host}:${Port}
    &{data}=    Create Dictionary    client_id    ${clientId}
    &{headers}=    Create Dictionary    Content-Type=application/json
    ${resp}=    Post Request    server    /client/services    data=${data}    headers=${headers}
    Should Be Equal As Strings    ${resp.status_code}    200
    Should Not Be Equal As Integers    ${resp.json()['count']}    0
    ${listClientServices} =    Create List
    : FOR    ${item}    IN    @{resp.json()['items']}
    \    Log    ${item}
    \    Append To List    ${listClientServices}    ${item['id']}
    ${vsp}=    Convert To Integer    ${idServices}
    List Should Contain Value    ${listClientServices}    ${vsp}
