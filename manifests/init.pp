class lvmsync {
	package { "lvmsync":
		provider => "gem",
		ensure   => "present"
	}
}
