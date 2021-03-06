class KeytechBomElement
	attr_accessor :simpleElement
	attr_accessor :keyValueList


def initialize
	keyValueList = {}
end


def to_json
	
	hash = {}
	self.instance_variables.each do |var|
		
		variableName = var.to_s.sub("@","")

		if variableName !="keyValueList"
			hash[variableName] = self.instance_variable_get var
		end
	end
	
	# Convert the inner attributes to JSOn object
	if self.keyValueList
		self.keyValueList.each do |pairs|
			hash[pairs['Key']] = pairs['Value']
		end
	end

	hash.to_json
end



end