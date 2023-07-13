bring cloud;
bring ex;
bring http;
bring util;
bring "cdktf" as cdktf;

class Utils {
  extern "./utils.js" static inflight base64decode(value: str): str;
  init() { }
}

let bucket = new cloud.Bucket() as "state-bucket";
let lockBucket = new cloud.Bucket() as "lock-bucket";
let authTable = new ex.Table(name: "auth", primaryKey: "userId", columns: {
  "userId" => ex.ColumnType.STRING,
  "password" => ex.ColumnType.STRING
});

class BasicAuth {
  authTable: ex.Table;

  init(table: ex.Table) {
    this.authTable = table;
  }

  inflight authHandler(req: cloud.ApiRequest): bool {
    if (req.headers?.has("authorization") == false) && (req.headers?.has("Authorization") == false) {
      log("headers: ${Json.stringify(req.headers)}");
      log("no auth header");
      return false;
    }
    let authHeaderOptional = req.headers?.get("authorization");
    let var authHeader = req.headers?.get("Authorization");

    if (authHeader == nil) {
      authHeader = authHeaderOptional;
    }

    if (authHeader == nil) {
      log("no auth header");
      return false;
    }

    let auth = Utils.base64decode("${authHeader}".split(" ").at(1));
    let splittedAuth = auth.split(":");
    let username = splittedAuth.at(0);
    let password = splittedAuth.at(1);
    return this.basicAuth(username, password);
  }

  inflight basicAuth(username: str, password: str): bool {
    let user: Json? = authTable.get(username);
    if (user == nil) {
      log("user not found");
      return false;
    }
    log("user found");
    let matched = user?.get("password")?.asStr() == password;
    log("password matched: ${matched}");
    return user?.get("password")?.asStr() == password;
  }
}

class BasicAuth {
  authTable: ex.Table;

  init(table: ex.Table) {
    this.authTable = table;
  }

  inflight getState(req: cloud.ApiRequest): cloud.ApiResponse => {
    if(!auth_handler(req)){
      log("auth failed");
      return cloud.ApiResponse {status: 403};
    }

    let project = req.vars.get("project");
    if let state = bucket.tryGetJson(project) {
      return cloud.ApiResponse {
        status: 200,
        headers: {"Content-Type" => "application/json"},
        body: Json.stringify(state),
      };
    } else {
      log("project not found");
      return cloud.ApiResponse {status: 404};
    }
  }
}

let projectPath = "/project";


let post_state_handler = inflight(req: cloud.ApiRequest): cloud.ApiResponse => {
  if(!auth_handler(req)){
    return cloud.ApiResponse {status: 403};
  }

  let project = req.vars.get("project");
  let lockId = req.query.get("ID");

  log("lockId: ${lockId}");
  log("project: ${project}");

  if (lockBucket.tryGet(lockId) != nil){
    return cloud.ApiResponse {status: 423};
  }

  if let body = req.body {
    let state = Json.parse(body);
    log("state: ${Json.stringify(state)}");
    bucket.put(project, Json.stringify(state));

    return cloud.ApiResponse {
      status: 204,
      headers: {"Content-Type" => "application/json"}
    };
  } else {
    return cloud.ApiResponse {status: 400};
  }
};

let delete_state_handler = inflight(req: cloud.ApiRequest): cloud.ApiResponse => {
  if(!auth_handler(req)){
    return cloud.ApiResponse {status: 403};
  }

  let project = req.vars.get("project");
  bucket.delete(project);

  return cloud.ApiResponse {status: 200};
};

let lock_handler = inflight(req: cloud.ApiRequest): cloud.ApiResponse => {
  if(!auth_handler(req)){
    return cloud.ApiResponse {status: 403};
  }

  if let lockId = req.body {
    if (lockBucket.tryGet(lockId) == nil){
      lockBucket.put(lockId, "locked");
      return cloud.ApiResponse {status: 200};
    } else {
      return cloud.ApiResponse {status: 423};
    }
  } else {
    return cloud.ApiResponse {status: 400};
  }
};

let unlock_handler = inflight(req: cloud.ApiRequest): cloud.ApiResponse => {
  if(!auth_handler(req)){
    return cloud.ApiResponse {status: 403};
  }

  if let lockId = req.body {
    lockBucket.delete(lockId);
    return cloud.ApiResponse {status: 200};
  } else {
    return cloud.ApiResponse {status: 400};
  }
};

let createUser = new cloud.Function(inflight(eventStr: str): void => {
  // workaround since eventStr is already Json
  let event = Json.parse("${Json.stringify(eventStr)}");
  let username = event.get("username").asStr();
  // seems to return always nil
  let user = authTable.get(username).tryAsStr();
  if (user == nil) {
    authTable.insert(username, {
      password: event.get("password").asStr()
    });
  } else {
    log("user already exists");
  }
}) as "create-user";

let api = new cloud.Api();

api.get("${projectPath}/{project}", get_state_handler);
api.post("${projectPath}/{project}", post_state_handler);
api.delete("${projectPath}/{project}", delete_state_handler);
api.post("${projectPath}/{project}/lock", lock_handler);
api.post("${projectPath}/{project}/unlock", unlock_handler);

new cdktf.TerraformOutput(
  value: api.url,
) as "terraform-backend-url";

// ~~~ TESTS ~~~

class TestUtils {
  init() {}
}

class TestUser {
  username: str;
  password: str;

  extern "./test-utils.js" inflight base64encode(value: str): str;

  init(username: str, password: str) {
    this.username = username;
    this.password = password;
  }

  inflight create() {
    authTable.insert(this.username, {
      password: this.password
    });
  }

  inflight delete() {
    authTable.delete(this.username);
  }

  inflight getAuthHeader(): str {
    return "Basic " + this.base64encode(this.username + ":" + this.password);
  }
}
// this can't be an inflight class right now due to
// https://github.com/winglang/wing/issues/2730
let user = new TestUser("test-user", "test-password");
let otherUser = new TestUser("other-test-user", "test-password") as "otherUser";

let getProject = inflight(project: str): http.Response => {
  let response = http.get("${api.url}/project/" + project, {
    headers: {"Authorization": user.getAuthHeader()}
  });
  return response;
};

// ~~~ TESTS GET /project/:project ~~~

test "GET /project/:project" {
  let project = "test-project";
  let state = Json.parse("{\"foo\": \"bar\"}");

  user.create();

  bucket.put(project, Json.stringify(state));

  let response = getProject(project);
  log("${response.status} ${response.body}");
  log("${api.url}/project/" + project);
  log("${user.getAuthHeader()}");

  assert(response.status == 200);
  assert(response.body == Json.stringify(state));

  user.delete();
}

test "GET /project/:project (unauthorized, missing header)" {
  let project = "test-project";
  let state = Json.parse("{\"foo\": \"bar\"}");

  user.create();

  bucket.put(project, Json.stringify(state));
  let response = http.get("${api.url}/project/" + project);

  assert(response.status == 403);
  assert(response.body == "");

  user.delete();
}

test "GET /project/:project (unauthorized, wrong header)" {
  let project = "test-project";
  let state = Json.parse("{\"foo\": \"bar\"}");

  user.create();

  bucket.put(project, Json.stringify(state));
  let response = http.get("${api.url}/project/" + project, {
    headers: {"Authorization": "Basic " + user.base64encode("wrong-user:wrong-password")}
  });

  assert(response.status == 403);
  assert(response.body == "");

  user.delete();
}

test "GET /project/:project (project does not exist)" {
  let project = "test-project";
  let state = Json.parse("{\"foo\": \"bar\"}");

  user.create();

  bucket.put(project, Json.stringify(state));
  let response = http.get("${api.url}/project/" + "other-project", {
    headers: {"Authorization": user.getAuthHeader()}
  });

  assert(response.status == 404);
  assert(response.body == "");

  user.delete();
}

// ~~~ TESTS POST /project/:project ~~~

test "POST /project/:project" {
  let project = "test-project";
  let state = Json.parse("{\"foo\": \"bar\"}");
  let newState = Json.parse("{\"foo\": \"baz\"}");

  user.create();

  bucket.putJson(project, state);
  let response = http.post("${api.url}/project/" + project, http.RequestOptions {
    body: Json.stringify(newState),
    headers: { "Authorization" => user.getAuthHeader() }
  });

  assert(response.status == 204);
  assert(response.body == "");
  assert(Json.stringify(bucket.getJson(project)) == Json.stringify(newState));

  let newStoredState = getProject(project);
  assert(newStoredState.body == Json.stringify(newState));

  user.delete();
}

test "POST /project/:project (unauthorized, missing header)" {
  let project = "test-project";
  let state = Json.parse("{\"foo\": \"bar\"}");
  let newState = Json.parse("{\"foo\": \"baz\"}");

  user.create();

  bucket.put(project, Json.stringify(state));
  let response = http.post("${api.url}/project/" + project, http.RequestOptions {
    body: Json.stringify(newState)
  });

  assert(response.status == 403);
  assert(response.body == "");

  let storedState = getProject(project);
  assert(storedState.body == Json.stringify(state));

  user.delete();
}

test "POST /project/:project (unauthorized, wrong header)" {
  let project = "test-project";
  let state = Json.parse("{\"foo\": \"bar\"}");
  let newState = Json.parse("{\"foo\": \"baz\"}");

  user.create();

  bucket.put(project, Json.stringify(state));
  let response = http.post("${api.url}/project/" + project, http.RequestOptions {
    body: Json.stringify(newState),
    headers: {"Authorization" => "Basic " + user.base64encode("wrong-user:wrong-password")}
  });

  assert(response.status == 403);
  assert(response.body == "");

  let storedState = getProject(project);
  assert(storedState.body == Json.stringify(state));

  user.delete();
}

test "POST /project/:project (project does not exist yet)" {
  let project = "test-project";
  let newState = Json.parse("{\"foo\": \"baz\"}");

  user.create();

  let response = http.post("${api.url}/project/" + project, http.RequestOptions {
    body: Json.stringify(newState),
    headers: {"Authorization" => user.getAuthHeader()}
  });

  assert(response.status == 204);
  assert(response.body == "");

  let storedState = getProject(project);
  assert(storedState.body == Json.stringify(newState));

  user.delete();
}

test "POST /project/:project (project is locked)" {
  let project = "test-project";
  let state = Json.parse("{\"foo\": \"bar\"}");
  let newState = Json.parse("{\"foo\": \"baz\"}");

  let lockId = "132r23";
  lockBucket.put(lockId, lockId);
  user.create();

  bucket.put(project, Json.stringify(state));

  let response = http.post("${api.url}/project/" + project + "?ID=${lockId}", http.RequestOptions {
    body: Json.stringify(newState),
    headers: {"Authorization" => user.getAuthHeader()}
  });

  assert(response.status == 423);
  assert(response.body == "");

  let storedState = getProject(project);
  assert(storedState.body == Json.stringify(state));

  user.delete();
}