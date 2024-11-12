import Config

config :serverlog_daemon,
  pubsub_server: :pub_sub,
  file_load_warning_timeout: 10,
  file_path: "/tmp/"

config :logger, backends: []
