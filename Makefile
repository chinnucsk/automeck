## Copyright (c) 2011 Opscode, Inc.  All Rights Reserved.
##
## This file is provided to you under the Apache License,
## Version 2.0 (the "License"); you may not use this file
## except in compliance with the License.  You may obtain
## a copy of the License at
##
##   http://www.apache.org/licenses/LICENSE-2.0
##
## Unless required by applicable law or agreed to in writing,
## software distributed under the License is distributed on an
## "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
## KIND, either express or implied.  See the License for the
## specific language governing permissions and limitations
## under the License.
DEPS = deps/meck
all: compile

$(DEPS):
	@./rebar get-deps

compile: $(DEPS)
	@./rebar compile

clean:
	@./rebar clean

distclean:
	@rm -rf deps ebin/*