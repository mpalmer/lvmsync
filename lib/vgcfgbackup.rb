module VgCfgBackup
	class Node < Treetop::Runtime::SyntaxNode
	end

	class Group < Node
		def name
			self.elements[0].text_value
		end

		def variables
			self.elements[3].elements.select { |e| e.is_a? Variable }
		end

		def variable_value(name)
			self.variables.find { |v| v.name == name }.value rescue nil
		end

		def groups
			self.elements[3].elements.select { |e| e.is_a? Group }.inject({}) { |h,v| h[v.name] = v; h }
		end
	end

	class Config < Group
		def name
			nil
		end

		def variables
			self.elements.select { |e| e.is_a? Variable }
		end

		def groups
			self.elements.select { |e| e.is_a? Group }.inject({}) { |h,v| h[v.name] = v; h }
		end
	end

	class Variable < Node
		def name
			self.elements[0].text_value
		end

		def value
			self.elements[2].value
		end
	end

	class VariableName < Node
	end

	class Integer < Node
		def value
			self.text_value.to_i
		end
	end

	class String < Node
		def value
			self.elements[1].text_value
		end
	end

	class List < Node
		def value
			self.elements.find { |e| e.is_a?(String) }.map { |e| e.value }
		end
	end
end
