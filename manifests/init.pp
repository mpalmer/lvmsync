class lvmsync {
	file { "/usr/local/sbin/lvmsync":
		ensure  => file,
		source  => "puppet:///modules/lvmsync/lvmsync",
		mode    => 0555,
		owner   => root,
		group   => root
	}
}
