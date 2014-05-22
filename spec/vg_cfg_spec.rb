require 'lvm/vg_config'

describe LVM::VGConfig do
	let(:vgcfg) do
		LVM::VGConfig.new(
		        vg_name,
		        :vgcfgbackup_command => File.expand_path(
		                                       '../fixtures/vgcfgbackup',
		                                       __FILE__
		                                     )
		      )
	end

	context "trivial config" do
		let(:vg_name) { "trivial" }

		it "parses successfully" do
			expect { vgcfg }.to_not raise_error
		end

		it "Gives us back a VgCfg" do
			expect(vgcfg).to be_an(LVM::VGConfig)
		end

		it "has a version" do
			expect(vgcfg.version).to eq(1)
		end

		it "has a description" do
			expect(vgcfg.description).to eq("vgcfgbackup -f /tmp/faffen2")
		end
	end

	context "volume group metadata" do
		let(:vg_name) { "vgmetadata" }

		it "parses successfully" do
			expect { vgcfg }.to_not raise_error
		end

		it "has a UUID" do
			expect(vgcfg.uuid).to match(/^[A-Za-z0-9-]+$/)
		end
	end

	context "physical volume" do
		let(:vg_name) { "physicalvolume" }

		it "parses successfully" do
			expect { vgcfg }.to_not raise_error
		end

		it "is its own class" do
			expect(vgcfg.physical_volumes["pv0"]).to be_an(LVM::PVConfig)
		end
	end

	context "complete config" do
		let(:vg_name) { "fullconfig" }

		it "parses successfully" do
			expect { vgcfg }.to_not raise_error
		end

		it "contains logical volumes" do
			expect(vgcfg.logical_volumes).to be_a(Hash)

			vgcfg.logical_volumes.values.each { |lv| expect(lv).to be_an(LVM::LVConfig) }
		end

		it "has an LV named thintest" do
			expect(vgcfg.logical_volumes['thintest']).to_not be(nil)
		end

		context "thintest LV" do
			let(:lv) { vgcfg.logical_volumes['thintest'] }

			it "is thin" do
				expect(lv.thin?).to be(true)
			end

			it "is not a snapshot" do
				expect(lv.snapshot?).to be(false)
			end

			it "belongs to 'thinpool'" do
				expect(lv.thin_pool).to eq("thinpool")
			end

			it "has device_id of 1" do
				expect(lv.device_id).to eq(1)
			end
		end

		it "has an LV named thinsnap2" do
			expect(vgcfg.logical_volumes['thinsnap2']).to_not be(nil)
		end

		context "thinsnap2 LV" do
			let(:lv) { vgcfg.logical_volumes['thinsnap2'] }

			it "is thin" do
				expect(lv.thin?).to be(true)
			end

			it "belongs to 'thinpool'" do
				expect(lv.thin_pool).to eq("thinpool")
			end

			it "has device_id of 3" do
				expect(lv.device_id).to eq(3)
			end

			it "is a snapshot" do
				expect(lv.snapshot?).to be(true)
			end

			it "is a snapshot of 'thintest'" do
				expect(lv.origin).to eq('thintest')
			end
		end

		context "snapshot0 LV" do
			let(:lv) { vgcfg.logical_volumes['snapshot0'] }

			it "has a CoW store" do
				expect(lv.cow_store).to eq('rootsnap')
			end

			it "is not thin" do
				expect(lv.thin?).to be(false)
			end

			it "is not a snapshot" do
				expect(lv.snapshot?).to be(false)
			end
		end

		context "rootsnap LV" do
			let(:lv) { vgcfg.logical_volumes['rootsnap'] }

			it "is not thin" do
				expect(lv.thin?).to be(false)
			end

			it "is a snapshot" do
				expect(lv.snapshot?).to be(true)
			end
		end

		context "thinpool" do
			let(:lv) { vgcfg.logical_volumes['thinpool'] }

			it "has a chunk size" do
				expect(lv.chunk_size).to eq(65536)
			end

			it "is not thin" do
				expect(lv.thin?).to be(false)
			end

			it "is not a snapshot" do
				expect(lv.snapshot?).to be(false)
			end
		end
	end
end
