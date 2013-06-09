class lvmsync {
	file { "/usr/local/sbin/lvmsync":
		ensure  => present,
		content => template("lvmsync/lvmsync"),
		mode    => 0444,
		owner   => root,
		group   => root
	}
}
