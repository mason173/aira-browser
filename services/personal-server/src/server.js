const http = require('http');
const { host, port, setupCodePath } = require('./config');
const { databasePath } = require('./db/database');
const { handleRequest } = require('./app');
const { initializeInstance } = require('./instance');

const instance = initializeInstance();
const server = http.createServer(handleRequest);

server.listen(port, host, () => {
  console.log(`Aira Personal Server ${instance.instance_id} listening on ${host}:${port}`);
  console.log(`Database: ${databasePath}`);
  if (instance.setupCode) {
    console.log(`A one-time setup code was written with mode 0600 to ${setupCodePath}.`);
  }
});
