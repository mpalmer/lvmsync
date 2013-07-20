class lvmsync {
	file { "/usr/local/sbin/lvmsync":
		ensure  => present,
		source  => "puppet:///modules/lvmsync/lvmsync",
		mode    => 0555,
		owner   => root,
		group   => root
	}
}
