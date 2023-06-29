bring cloud;
bring http;

class Utils {
  extern "./utils.js" static inflight base64decode(str: str): str;
  init() { }
}

let bucket = new cloud.Bucket() as "state-bucket";
let lockBucket = new cloud.Bucket() as "lock-bucket";
let authTable = new cloud.Table(name: "auth", primaryKey: "userId", columns: {
  userId: cloud.ColumnType.STRING,
  password: cloud.ColumnType.STRING
});

let basic_auth = inflight (username: str, password: str): bool => {
  let user = authTable.get(username);
  if (user == nil) {
    log("user not found");
    return false;
  }
  return user.get("password") == password;
};

let projectPath = "/project";

let auth_handler = inflight(req: cloud.ApiRequest): bool => {
  if (req.headers?.has("authorization") == false) {
    return false;
  }

  let auth = Utils.base64decode(req.headers?.get("authorization").split(" ").at(1));
  let splittedAuth = auth.split(":");
  let username = splittedAuth.at(0);
  let password = splittedAuth.at(1);
  return basic_auth(username, password);
};

let get_state_handler = inflight(req: cloud.ApiRequest): cloud.ApiResponse => {
  if(!auth_handler(req)){
    log("auth failed");
    return cloud.ApiResponse {status: 403};
  }

  let project = req.vars.get("project");
  if let state = bucket.tryGetJson(project) {
    return cloud.ApiResponse {
      status: 200,
      headers: {"Content-Type": "application/json"},
      body: Json.stringify(state),
    };
  } else {
    log("project not found");
    return cloud.ApiResponse {status: 404};
  }
};

let post_state_handler = inflight(req: cloud.ApiRequest): cloud.ApiResponse => {
  if(!auth_handler(req)){
    return cloud.ApiResponse {status: 403};
  }

  let project = req.vars.get("project");
  let lockId = req.query.get("lock_id");

  if (lockBucket.tryGet(lockId) != nil){
    return cloud.ApiResponse {status: 423};
  }

  let foo = Json {
    "foo": "bar"
  };

  if let body = req.body {
    let state = Json.parse(body);
    bucket.put(project, Json.stringify(state));

    return cloud.ApiResponse {
      status: 204,
      headers: {"Content-Type": "application/json"}
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

let api = new cloud.Api();
api.get("${projectPath}/{project}", get_state_handler);
api.post("${projectPath}/{project}", post_state_handler);
api.delete("${projectPath}/{project}", delete_state_handler);
api.post("${projectPath}/{project}/lock", lock_handler);
api.post("${projectPath}/{project}/unlock", unlock_handler);

// ~~~ TESTS ~~~

class TestUtils {
  init() {}
}

class TestUser {
  username: str;
  password: str;

  extern "./test-utils.js" inflight base64encode(str: str): str;

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


// ~~~ TESTS GET /project/:project ~~~

test "GET /project/:project" {
  let project = "test-project";
  let state = Json.parse("{\"foo\": \"bar\"}");

  user.create();

  bucket.put(project, Json.stringify(state));
  let response = http.get("${api.url}/project/" + project, {
    headers: {"Authorization": user.getAuthHeader()}
  });

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
    headers: {"Authorization": user.getAuthHeader()}
  });

  assert(response.status == 204);
  assert(response.body == "");
  assert(Json.stringify(bucket.getJson(project)) == Json.stringify(newState));

  let newStoredState = http.get("${api.url}/project/" + project, {
    headers: {
      "Authorization": user.getAuthHeader()
    }
  });
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

  let storedState = http.get("${api.url}/project/" + project, {
    headers: {
      "Authorization": user.getAuthHeader()
    }
  });
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
    headers: {"Authorization": "Basic " + user.base64encode("wrong-user:wrong-password")}
  });

  assert(response.status == 403);
  assert(response.body == "");

  let storedState = http.get("${api.url}/project/" + project, {
    headers: {
      "Authorization": user.getAuthHeader()
    }
  });
  assert(storedState.body == Json.stringify(state));

  user.delete();
}

test "POST /project/:project (project does not exist yet)" {
  let project = "test-project";
  let newState = Json.parse("{\"foo\": \"baz\"}");

  user.create();

  let response = http.post("${api.url}/project/" + project, http.RequestOptions {
    body: Json.stringify(newState),
    headers: {"Authorization": user.getAuthHeader()}
  });

  assert(response.status == 204);
  assert(response.body == "");

  let storedState = http.get("${api.url}/project/" + project, {
    headers: {
      "Authorization": user.getAuthHeader()
    }
  });
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

  let response = http.post("${api.url}/project/" + project + "?lock_id=${lockId}", http.RequestOptions {
    body: Json.stringify(newState),
    headers: {"Authorization": user.getAuthHeader()}
  });

  assert(response.status == 423);
  assert(response.body == "");

  let storedState = http.get("${api.url}/project/" + project, {
    headers: {
      "Authorization": user.getAuthHeader()
    }
  });
  assert(storedState.body == Json.stringify(state));

  user.delete();
}