class lvmsync {
	file { "/usr/local/sbin/lvmsync":
		ensure  => present,
		content => template("lvmsync/lvmsync"),
		mode    => 0555,
		owner   => root,
		group   => root
	}
}
