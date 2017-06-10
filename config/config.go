package config

type Configuration struct {
	Users           []string
	Groups          []string
	ConnectTopic    string
	DisconnectTopic string
	CommandTopic    string
}

const (
	connect    = "/status/connect"
	disconnect = "/status/disconnect"
	command    = "/client/%s/command"
)

func GetConfig() (Configuration, error) {
	c := Configuration{ConnectTopic: connect, DisconnectTopic: disconnect}
	return c, nil
}
