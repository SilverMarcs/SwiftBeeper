package config

// Config contains only the local profile and Beeper connection settings.
type Config struct {
	AccessToken         string
	ManageSecret        string
	StateDir            string
	MatrixHomeserverURL string
}
