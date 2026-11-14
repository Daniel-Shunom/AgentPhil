import gleam/dict
import gleam/list
import youid/uuid

pub type AgentJob {
  AgentJob(
    id: String,
    user_messages: List(String),
    tools: dict.Dict(ToolID, Tool),
    steps: Int,
    status: AgentJobStatus,
  )
}

pub type ToolID {
  ToolID(id: String)
}

pub type Tool {
  AgentTool(tool: String, args: List(String))
}

pub type AgentJobID {
  AgentJobID(id: String)
}

pub type AgentJobStatus {
  Pending
  Running
  Completed
  NotRegistered
  JobNotFound
}

pub type AgentJobRegistry {
  AgentJobRegistry(registry: dict.Dict(AgentJobID, AgentJob))
}

// pub type ToolRegistry {
//   ToolRegistry(
//     registry: dict.Dict(ToolID, Tool)
//   )
// }

pub type RegistryError {
  CouldNotRegister
  JobAlreadyExists
}

pub fn create_job_registry() -> AgentJobRegistry {
  AgentJobRegistry(registry: dict.new())
}

pub fn register_agent_job(
  registry: AgentJobRegistry,
  job_id: AgentJobID,
  job: AgentJob,
) -> Result(AgentJobRegistry, RegistryError) {
  case dict.has_key(registry.registry, job_id) {
    False -> {
      let new_registry =
        registry.registry
        |> dict.insert(job_id, job)
        |> AgentJobRegistry
      Ok(new_registry)
    }
    True -> Error(JobAlreadyExists)
  }
}

pub fn check_job_status(
  registry: AgentJobRegistry,
  job_id: AgentJobID,
) -> AgentJobStatus {
  case dict.get(registry.registry, job_id) {
    Error(Nil) -> JobNotFound
    Ok(job) -> job.status
  }
}

pub fn create_agent_job(id: String) -> AgentJob {
  AgentJob(
    id: id,
    user_messages: [],
    tools: dict.new(),
    steps: default_steps,
    status: Pending,
  )
}

pub fn add_user_msg_to_job(job: AgentJob, msg: String) -> AgentJob {
  AgentJob(..job, user_messages: list.prepend(job.user_messages, msg))
}

pub fn add_tool_to_job(job: AgentJob, tool_id: ToolID, tool: Tool) -> AgentJob {
  let new_tools = dict.insert(job.tools, tool_id, tool)
  AgentJob(..job, tools: new_tools)
}

pub fn set_job_status(job: AgentJob, status: AgentJobStatus) -> AgentJob {
  AgentJob(..job, status:)
}

pub fn set_job_steps(job: AgentJob, steps: Int) -> AgentJob {
  AgentJob(..job, steps: steps)
}

pub fn generate_job_id() -> AgentJobID {
  AgentJobID(id: "@agent_job-" <> uuid.v1_string())
}

pub fn generate_agent_id() -> ToolID {
  ToolID(id: "@agent_tool-" <> uuid.v4_string())
}

pub const default_steps = 10
